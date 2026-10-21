// Simulation template only: no functional PASS claim.
`timescale 1ns/1ps
module tb_clk_gen;
    reg clk=0;
    reg rst_n=0;
    always #18.5185 clk=~clk; // approximate 27MHz in simulation
    wire sample_en,bclk,lrclk,bit_fall_ce,frame_load; wire [4:0] bit_index;
    clk_gen dut (.clk(clk),.rst_n(rst_n),.sample_en(sample_en),.bclk(bclk),.lrclk(lrclk),.bit_fall_ce(bit_fall_ce),.bit_index(bit_index),.frame_load(frame_load));
    initial begin
        $dumpfile("sim/tb_clk_gen.vcd");
        $dumpvars(0,tb_clk_gen);
        repeat(5) @(negedge clk);
        rst_n=1;
        // TODO: assert BCLK half-period=9 clocks; frame period=576 clocks.
        repeat(2000) @(negedge clk);
        $display("TEMPLATE FINISHED: functionality not verified");
        $finish;
    end
endmodule
