`timescale 1ns/1ps
module tb_control_panel;
    reg clk, rst_n;
    reg timbre_key, bend_up_key, bend_down_key, volume_up_key, volume_down_key;
    wire [1:0] timbre;
    wire signed [3:0] bend;
    wire [15:0] master_gain;
    localparam CTRL = 4;   // small value for fast simulation

    control_panel #(.CTRL_FILT(CTRL)) dut (
        .clk(clk), .rst_n(rst_n),
        .timbre_key(timbre_key), .bend_up_key(bend_up_key),
        .bend_down_key(bend_down_key), .volume_up_key(volume_up_key),
        .volume_down_key(volume_down_key),
        .timbre(timbre), .bend(bend), .master_gain(master_gain)
    );

    always #10 clk = ~clk;
    task wait_cycles; input integer n; integer j; begin for (j=0;j<n;j=j+1) @(posedge clk); end endtask

    integer pass;
    initial begin
        $dumpfile("sim/tb_control_panel.vcd");
        $dumpvars(0, tb_control_panel);
        pass = 1;
        clk = 0; rst_n = 0;
        timbre_key=0; bend_up_key=0; bend_down_key=0; volume_up_key=0; volume_down_key=0;
        wait_cycles(2); rst_n = 1; wait_cycles(2);

        if (master_gain !== 16'd16384) begin $display("FAIL reset gain = %0d", master_gain); pass = 0; end

        // ---- timbre toggle (once per press) ----
        timbre_key = 1; wait_cycles(CTRL + 3); timbre_key = 0; wait_cycles(CTRL + 2);
        if (timbre !== 2'd1) begin $display("FAIL timbre ->1 = %b", timbre); pass = 0; end
        timbre_key = 1; wait_cycles(CTRL + 3); timbre_key = 0; wait_cycles(CTRL + 2);
        if (timbre !== 2'd0) begin $display("FAIL timbre ->0 = %b", timbre); pass = 0; end

        // ---- bend up ----
        bend_up_key = 1; wait_cycles(CTRL + 3);
        if (bend !== 4'sb0010) begin $display("FAIL bend up = %0d", bend); pass = 0; end
        bend_up_key = 0; wait_cycles(CTRL + 3);
        if (bend !== 4'sb0000) begin $display("FAIL bend off = %0d", bend); pass = 0; end
        // ---- bend down ----
        bend_down_key = 1; wait_cycles(CTRL + 3);
        if (bend !== 4'sb1110) begin $display("FAIL bend down = %0d", bend); pass = 0; end
        bend_down_key = 0; wait_cycles(CTRL + 3);
        if (bend !== 4'sb0000) begin $display("FAIL bend off2 = %0d", bend); pass = 0; end
        // ---- both -> 0 ----
        bend_up_key = 1; bend_down_key = 1; wait_cycles(CTRL + 3);
        if (bend !== 4'sb0000) begin $display("FAIL bend both = %0d", bend); pass = 0; end
        bend_up_key = 0; bend_down_key = 0; wait_cycles(CTRL + 3);

        // ---- volume up one step ----
        volume_up_key = 1; wait_cycles(CTRL + 3); volume_up_key = 0; wait_cycles(CTRL + 2);
        if (master_gain !== 16'd20480) begin $display("FAIL vol up = %0d", master_gain); pass = 0; end
        // ---- clamp high (no wrap) ----
        repeat (20) begin volume_up_key = 1; wait_cycles(CTRL + 3); volume_up_key = 0; wait_cycles(CTRL + 2); end
        if (master_gain !== 16'd65535) begin $display("FAIL vol clamp hi = %0d", master_gain); pass = 0; end
        // ---- clamp low (no wrap) ----
        repeat (20) begin volume_down_key = 1; wait_cycles(CTRL + 3); volume_down_key = 0; wait_cycles(CTRL + 2); end
        if (master_gain !== 16'd0) begin $display("FAIL vol clamp lo = %0d", master_gain); pass = 0; end

        if (pass) begin
            $display("PASS: tb_control_panel all checks passed");
            $finish;
        end else begin
            $display("FAIL: tb_control_panel");
            $finish;
        end
    end
endmodule
