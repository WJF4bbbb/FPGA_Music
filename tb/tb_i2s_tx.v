// Simulation template only: no functional PASS claim.
`timescale 1ns/1ps
module tb_i2s_tx;
    reg clk=0;
    reg rst_n=0;
    always #18.5185 clk=~clk; // approximate 27MHz in simulation
    reg signed [15:0] sample=0; reg sample_valid=0; reg bit_fall_ce=0; reg [4:0] bit_index=0; reg frame_load=0; wire data; wire [31:0] underrun_count;
    i2s_tx dut (.clk(clk),.rst_n(rst_n),.sample(sample),.sample_valid(sample_valid),.bit_fall_ce(bit_fall_ce),.bit_index(bit_index),.frame_load(frame_load),.data(data),.underrun_count(underrun_count));
    initial begin
        $dumpfile("sim/tb_i2s_tx.vcd");
        $dumpvars(0,tb_i2s_tx);
        repeat(5) @(negedge clk);
        rst_n=1;
        // TODO: drive edge enables and verify serialized 0000/7FFF/8000/A55A.
        repeat(2000) @(negedge clk);
        $display("TEMPLATE FINISHED: functionality not verified");
        $finish;
    end
endmodule
