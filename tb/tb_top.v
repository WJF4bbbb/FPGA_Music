// Simulation template only: no functional PASS claim.
`timescale 1ns/1ps
module tb_top;
    reg clk=0;
    reg rst_n=0;
    always #18.5185 clk=~clk; // approximate 27MHz in simulation
    reg [7:0] key_raw=0; reg timbre_key=0,bend_up_key=0,bend_down_key=0,volume_up_key=0,volume_down_key=0,test_enable=0; wire bclk,lrclk,i2s_data;
    top dut (.clk(clk),.rst_n(rst_n),.key_raw(key_raw),.timbre_key(timbre_key),.bend_up_key(bend_up_key),.bend_down_key(bend_down_key),.volume_up_key(volume_up_key),.volume_down_key(volume_down_key),.test_enable(test_enable),.bclk(bclk),.lrclk(lrclk),.i2s_data(i2s_data));
    initial begin
        $dumpfile("sim/tb_top.vcd");
        $dumpvars(0,tb_top);
        repeat(5) @(negedge clk);
        rst_n=1;
        key_raw=8'h0F; repeat(20) @(posedge clk); key_raw=0; // TODO: audio assertions.
        repeat(2000) @(negedge clk);
        $display("TEMPLATE FINISHED: functionality not verified");
        $finish;
    end
endmodule
