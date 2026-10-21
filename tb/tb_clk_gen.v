`timescale 1ns/1ps
`default_nettype none
module tb_clk_gen;
    reg clk_27m=0, rst_n=1;
    wire clk_audio, pll_locked, audio_rst_n;
    integer n;
    always #18.519 clk_27m=~clk_27m;
    clk_gen #(.LOCK_STABLE_CYCLES(3)) dut (
        .clk_27m(clk_27m), .rst_n(rst_n), .clk_audio(clk_audio),
        .pll_locked(pll_locked), .audio_rst_n(audio_rst_n)
    );
    task check;
        input ok;
        input [511:0] message;
        begin
            if(ok !== 1'b1) begin
                $display("FAIL: %0s",message);
                $finish_and_return(1);
            end
        end
    endtask
    task startup;
        begin
            @(negedge clk_audio); dut.u_pll.lock_model=1;
            // Two synchronizer stages, then three qualification cycles.
            for(n=1;n<=5;n=n+1) begin
                @(posedge clk_audio); #1;
                check(audio_rst_n === (n==5), "release after 2 synchronization + 3 stable cycles");
            end
        end
    endtask
    initial begin
        $dumpfile("sim/tb_clk_gen.vcd"); $dumpvars(0,tb_clk_gen);
        #2 rst_n=0; #1;
        check(audio_rst_n===0,"external reset asserts asynchronously");
        #100 rst_n=1;
        repeat(4) begin @(posedge clk_audio); #1; check(audio_rst_n===0,"unlocked holds reset"); end
        startup;
        @(negedge clk_audio); #2 dut.u_pll.lock_model=0; #1;
        check(audio_rst_n===0,"loss of lock asserts asynchronously");
        // A short lock pulse cannot release reset.
        #2 dut.u_pll.lock_model=1;
        @(posedge clk_audio); #1;
        check(audio_rst_n===0,"short lock cannot release");
        #1 dut.u_pll.lock_model=0; #1;
        startup;
        @(negedge clk_audio); #2 rst_n=0; #1;
        check(audio_rst_n===0,"reset while running");
        repeat(3) @(negedge clk_audio);
        rst_n=1;
        for(n=1;n<=5;n=n+1) begin
            @(posedge clk_audio); #1;
            check(audio_rst_n === (n==5),"restart with lock already high");
        end
        $display("PASS: clk_gen reset control (simulation PLL substitute only)");
        $finish;
    end
    initial begin #10000; $display("FAIL: timeout"); $finish_and_return(1); end
endmodule

// TEST ONLY: independently generated clock is NOT a hardware PLL model.
// Never include this module in a synthesis source list.
module audio_pll_adapter (
    input wire clk_27m, input wire reset,
    output reg clk_audio=0, output wire locked
);
    reg lock_model=0;
    always #20.345 clk_audio=~clk_audio;
    assign locked=lock_model;
endmodule
`default_nettype wire
