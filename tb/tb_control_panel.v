`timescale 1ns/1ps
module tb_control_panel;
    reg clk, rst_n;
    reg timbre_key, bend_up_key, bend_down_key, volume_up_key, volume_down_key;
    wire [1:0] timbre;
    wire signed [3:0] bend;
    wire [15:0] master_gain;
    localparam CTRL = 4;   // small value for fast simulation
    localparam SYNC_CYCLES = 2;
    localparam OUTPUT_CYCLES = 1;
    localparam SETTLE_CYCLES = SYNC_CYCLES + CTRL + OUTPUT_CYCLES;
    localparam HOLD_CYCLES = 2 * SETTLE_CYCLES;
    integer pass;
    integer expected_gain;

    control_panel #(.CTRL_FILT(CTRL)) dut (
        .clk(clk), .rst_n(rst_n),
        .timbre_key(timbre_key), .bend_up_key(bend_up_key),
        .bend_down_key(bend_down_key), .volume_up_key(volume_up_key),
        .volume_down_key(volume_down_key),
        .timbre(timbre), .bend(bend), .master_gain(master_gain)
    );

    always #10 clk = ~clk;
    // Every caller drives/checks after a falling edge, away from DUT posedge NBA.
    // From here: E1 -> s1, E2 -> s2, E3..E(CTRL+2) -> debounce,
    // E(CTRL+3) -> registered output. No extra settling cycles are needed.
    task wait_cycles;
        input integer n;
        integer j;
        begin
            for (j=0; j<n; j=j+1) @(negedge clk);
            #1;
        end
    endtask

    task check_bend;
        input signed [3:0] expected;
        begin
            if (bend !== expected) begin
                $display("FAIL bend at t=%0t expected=%0d got=%0d", $time, expected, bend);
                pass = 0;
            end
        end
    endtask

    // Check every earlier sample, then return exactly when the new value is due.
    task wait_bend_transition;
        input signed [3:0] previous;
        integer j;
        begin
            for (j=0; j<SETTLE_CYCLES-1; j=j+1) begin
                wait_cycles(1);
                check_bend(previous);
            end
            wait_cycles(1);
        end
    endtask

    task hold_bend;
        input signed [3:0] expected;
        integer j;
        begin
            for (j=0; j<HOLD_CYCLES; j=j+1) begin
                wait_cycles(1);
                check_bend(expected);
            end
        end
    endtask

    task hold_timbre;
        input [1:0] expected;
        integer j;
        begin
            for (j=0; j<HOLD_CYCLES; j=j+1) begin
                wait_cycles(1);
                if (timbre !== expected) begin
                    $display("FAIL timbre repeated while held = %b", timbre);
                    pass = 0;
                end
            end
        end
    endtask

    task check_gain;
        input [15:0] expected;
        begin
            if (master_gain !== expected) begin
                $display("FAIL gain expected=%0d got=%0d", expected, master_gain);
                pass = 0;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_control_panel.vcd");
        $dumpvars(0, tb_control_panel);
        pass = 1;
        clk = 0; rst_n = 0;
        timbre_key=0; bend_up_key=0; bend_down_key=0; volume_up_key=0; volume_down_key=0;
        wait_cycles(2); rst_n = 1; wait_cycles(2);

        if (master_gain !== 16'd16384) begin $display("FAIL reset gain = %0d", master_gain); pass = 0; end
        if (timbre !== 2'd0) begin $display("FAIL reset timbre = %b", timbre); pass = 0; end
        check_bend(4'sd0);

        // A pulse with only CTRL-1 sampled highs must be rejected on all keys.
        timbre_key=1; bend_up_key=1; volume_up_key=1;
        wait_cycles(CTRL-1);
        timbre_key=0; bend_up_key=0; volume_up_key=0;
        wait_cycles(SETTLE_CYCLES);
        check_bend(4'sd0);
        check_gain(16'd16384);
        if (timbre !== 2'd0) begin $display("FAIL short timbre pulse accepted"); pass = 0; end

        // ---- timbre toggle (once per press) ----
        timbre_key = 1; wait_cycles(SETTLE_CYCLES); hold_timbre(2'd1);
        timbre_key = 0; wait_cycles(SETTLE_CYCLES);
        if (timbre !== 2'd1) begin $display("FAIL timbre ->1 = %b", timbre); pass = 0; end
        timbre_key = 1; wait_cycles(SETTLE_CYCLES); hold_timbre(2'd0);
        timbre_key = 0; wait_cycles(SETTLE_CYCLES);
        if (timbre !== 2'd0) begin $display("FAIL timbre ->0 = %b", timbre); pass = 0; end

        // ---- bend up ----
        bend_up_key = 1; wait_bend_transition(4'sd0);
        if (bend !== 4'sb0010) begin $display("FAIL bend up = %0d", bend); pass = 0; end
        hold_bend(4'sd2);
        bend_up_key = 0; wait_bend_transition(4'sd2);
        if (bend !== 4'sb0000) begin $display("FAIL bend off = %0d", bend); pass = 0; end
        hold_bend(4'sd0);
        // ---- bend down ----
        bend_down_key = 1; wait_bend_transition(4'sd0);
        if (bend !== 4'sb1110) begin $display("FAIL bend down = %0d", bend); pass = 0; end
        hold_bend(-4'sd2);
        bend_down_key = 0; wait_bend_transition(-4'sd2);
        if (bend !== 4'sb0000) begin $display("FAIL bend off2 = %0d", bend); pass = 0; end
        // ---- both -> 0 ----
        bend_up_key = 1; bend_down_key = 1; wait_bend_transition(4'sd0);
        if (bend !== 4'sb0000) begin $display("FAIL bend both = %0d", bend); pass = 0; end
        hold_bend(4'sd0);
        bend_up_key = 0; bend_down_key = 0; wait_bend_transition(4'sd0);
        check_bend(4'sd0);

        // Overlap/cancel an existing bend, then release only one of the two keys.
        bend_up_key = 1; wait_bend_transition(4'sd0); check_bend(4'sd2);
        bend_down_key = 1; wait_bend_transition(4'sd2); check_bend(4'sd0);
        bend_up_key = 0; wait_bend_transition(4'sd0); check_bend(-4'sd2);
        bend_down_key = 0; wait_bend_transition(-4'sd2); check_bend(4'sd0);
        bend_up_key = 1; bend_down_key = 1; wait_bend_transition(4'sd0); check_bend(4'sd0);
        bend_down_key = 0; wait_bend_transition(4'sd0); check_bend(4'sd2);
        bend_up_key = 0; wait_bend_transition(4'sd2); check_bend(4'sd0);

        // ---- volume up one step ----
        volume_up_key = 1; wait_cycles(SETTLE_CYCLES);
        repeat (HOLD_CYCLES) begin wait_cycles(1); check_gain(16'd20480); end
        volume_up_key = 0; wait_cycles(SETTLE_CYCLES);
        if (master_gain !== 16'd20480) begin $display("FAIL vol up = %0d", master_gain); pass = 0; end
        // ---- clamp high (no wrap) ----
        expected_gain = 20480;
        repeat (20) begin
            expected_gain = (expected_gain > 65535-4096) ? 65535 : expected_gain+4096;
            volume_up_key = 1; wait_cycles(SETTLE_CYCLES); check_gain(expected_gain);
            volume_up_key = 0; wait_cycles(SETTLE_CYCLES); check_gain(expected_gain);
        end
        if (master_gain !== 16'd65535) begin $display("FAIL vol clamp hi = %0d", master_gain); pass = 0; end
        // ---- clamp low (no wrap) ----
        expected_gain = 65535;
        repeat (20) begin
            expected_gain = (expected_gain < 4096) ? 0 : expected_gain-4096;
            volume_down_key = 1; wait_cycles(SETTLE_CYCLES); check_gain(expected_gain);
            repeat (HOLD_CYCLES) begin wait_cycles(1); check_gain(expected_gain); end
            volume_down_key = 0; wait_cycles(SETTLE_CYCLES); check_gain(expected_gain);
        end
        if (master_gain !== 16'd0) begin $display("FAIL vol clamp lo = %0d", master_gain); pass = 0; end

        // Reset after changing every output, and check that old key state is cleared.
        timbre_key = 1; bend_down_key = 1; volume_up_key = 1;
        wait_cycles(SETTLE_CYCLES);
        check_bend(-4'sd2); check_gain(16'd4096);
        if (timbre !== 2'd1) begin $display("FAIL pre-reset timbre"); pass = 0; end
        rst_n = 0;
        timbre_key=0; bend_down_key=0; volume_up_key=0;
        wait_cycles(2);
        check_bend(4'sd0); check_gain(16'd16384);
        if (timbre !== 2'd0) begin $display("FAIL running reset timbre"); pass = 0; end
        rst_n = 1; wait_cycles(SETTLE_CYCLES);
        check_bend(4'sd0); check_gain(16'd16384);
        if (timbre !== 2'd0) begin $display("FAIL stale timbre after reset"); pass = 0; end

        if (pass) begin
            $display("PASS: tb_control_panel all checks passed");
            $finish;
        end else begin
            $display("FAIL: tb_control_panel");
            $finish_and_return(1); // Icarus-only nonzero exit, as in A-group tests.
        end
    end
endmodule
