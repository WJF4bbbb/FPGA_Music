`timescale 1ns/1ps
`default_nettype none
// Same external-port test runs on RTL and the actual Gowin SDPB netlist.
module tb_wave_capture_mapped;
    reg clk=0,rst_n=0,start=0,release_capture=0,sample_valid=0;
    always #5 clk=~clk;
    reg signed [15:0] sample=0;
    reg [8:0] read_addr=0;
    wire signed [15:0] read_data;
    wire ready,busy,triggered;
    wave_capture dut(.*);
    function [15:0] reference_sample(input integer n);
        begin
            if(n==1) reference_sample=16'h8000;
            else if(n==2) reference_sample=16'h7fff;
            else reference_sample=n*149;
        end
    endfunction
    task push(input [15:0] value);
        begin
            @(negedge clk);sample=value;sample_valid=1;
            @(negedge clk);sample_valid=0;
        end
    endtask
    integer i;
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        push(-1);
        for(i=0;i<512;i=i+1) push(reference_sample(i));
        if(!ready || busy || !triggered) $fatal(1,"mapped trigger/completion mismatch");
        for(i=0;i<512;i=i+1) begin
            @(negedge clk);read_addr=i;
            @(posedge clk);#1;
            if(read_data!==reference_sample(i)) $fatal(1,"mapped RAM[%0d]=%h expected %h",i,read_data,reference_sample(i));
        end
        @(negedge clk);release_capture=1;
        @(negedge clk);release_capture=0;start=1;
        @(negedge clk);start=0;
        for(i=0;i<256+511;i=i+1) push(0);
        if(!ready || busy || triggered) $fatal(1,"mapped silence auto-trigger mismatch");
        for(i=0;i<512;i=i+1) begin
            @(negedge clk);read_addr=i;
            @(posedge clk);#1;
            if(read_data!==0) $fatal(1,"mapped silence RAM[%0d] stale",i);
        end
        $display("PASS: tb_wave_capture_mapped all 1024 production-size words and synchronous read latency");
        $finish;
    end
    initial begin #100000;$fatal(1,"mapped capture timeout");end
endmodule
`default_nettype wire
