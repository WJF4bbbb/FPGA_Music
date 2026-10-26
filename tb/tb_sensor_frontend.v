`timescale 1ns/1ps
module tb_sensor_frontend;
    reg clk, rst_n;
    reg [7:0] key_raw;
    wire [7:0] key_state;
    localparam FILT = 4;   // small value for fast simulation

    sensor_frontend #(.FILT_CYCLES(FILT)) dut (
        .clk(clk), .rst_n(rst_n), .key_raw(key_raw), .key_state(key_state)
    );

    always #10 clk = ~clk;
    task wait_cycles; input integer n; integer j; begin for (j=0;j<n;j=j+1) @(posedge clk); end endtask

    integer pass;
    initial begin
        $dumpfile("sim/tb_sensor_frontend.vcd");
        $dumpvars(0, tb_sensor_frontend);
        pass = 1;
        clk = 0; rst_n = 0; key_raw = 8'd0;
        wait_cycles(2);
        rst_n = 1;
        wait_cycles(2);

        // T1: a single key held beyond the filter is accepted
        key_raw[3] = 1'b1;
        wait_cycles(FILT - 1);                       // not yet stable
        if (key_state[3] !== 1'b0) begin $display("FAIL T1 early accept"); pass = 0; end
        wait_cycles(FILT + 1);                        // now stable
        if (key_state[3] !== 1'b1) begin $display("FAIL T1 not pressed"); pass = 0; end

        // T2: a glitch shorter than the filter is rejected
        key_raw[3] = 1'b0;                            // begin release
        wait_cycles(2);
        key_raw[3] = 1'b1;                            // glitch back before stable
        wait_cycles(2);
        if (key_state[3] !== 1'b1) begin $display("FAIL T2 glitch not rejected"); pass = 0; end
        key_raw[3] = 1'b0;                            // real release
        wait_cycles(FILT + 2);
        if (key_state[3] !== 1'b0) begin $display("FAIL T2 not released"); pass = 0; end

        // T3: multiple keys are filtered independently (no mutual masking)
        key_raw = 8'b10100101;
        wait_cycles(FILT + 2);
        if (key_state !== 8'b10100101) begin $display("FAIL T3 multi got %b", key_state); pass = 0; end

        if (pass) begin
            $display("PASS: tb_sensor_frontend all checks passed");
            $finish;
        end else begin
            $display("FAIL: tb_sensor_frontend");
            $finish;
        end
    end
endmodule
