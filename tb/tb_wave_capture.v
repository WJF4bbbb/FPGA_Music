`timescale 1ns/1ps
`default_nettype none
module tb_wave_capture;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, start=0, release_capture=0, sample_valid=0;
    reg signed [15:0] sample=0;
    reg [2:0] read_addr=0;
    wire signed [15:0] read_data;
    wire ready, busy, triggered;
    integer i;
    reg signed [15:0] expected [0:7];
    wave_capture #(.SAMPLE_COUNT(8),.ADDR_WIDTH(3),.TRIGGER_WAIT(4)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),.release_capture(release_capture),
        .sample(sample),.sample_valid(sample_valid),.read_addr(read_addr),
        .read_data(read_data),.ready(ready),.busy(busy),.triggered(triggered)
    );
    task push(input signed [15:0] value);
        begin
            @(negedge clk); sample=value; sample_valid=1;
            @(negedge clk); sample_valid=0; sample=16'sd12345;
            repeat(2) @(negedge clk);
        end
    endtask
    task request_capture;
        begin
            @(negedge clk); start=1;
            @(negedge clk); start=0;
        end
    endtask
    task free_capture;
        begin
            @(negedge clk); release_capture=1;
            @(negedge clk); release_capture=0;
        end
    endtask
    task check_memory;
        begin
            for(i=0;i<8;i=i+1) begin
                @(negedge clk); read_addr=i;
                @(posedge clk); #1;
                if(read_data !== expected[i])
                    $fatal(1,"RAM[%0d]=%0d expected %0d",i,read_data,expected[i]);
            end
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        request_capture();
        if(!busy || ready) $fatal(1,"capture request not accepted");
        // Invalid cycles and release requests must not terminate an acquisition.
        free_capture(); repeat(12) @(negedge clk);
        if(!busy || ready) $fatal(1,"invalid samples advanced capture");
        push(-16'sd5); push(-16'sd2); push(16'sd0);
        expected[0]=0; expected[1]=32767; expected[2]=-32768;
        expected[3]=-1; expected[4]=1; expected[5]=16'h55aa;
        expected[6]=-16'sd123; expected[7]=16'sd999;
        request_capture(); // Busy start cannot replace the zero-cross-triggered capture.
        for(i=1;i<8;i=i+1) push(expected[i]);
        if(!ready || busy || !triggered) $fatal(1,"zero-cross capture did not complete");
        check_memory();
        request_capture();
        for(i=0;i<12;i=i+1) push(16'sd22222);
        check_memory(); // Published RAM stays frozen while the UART is slow.
        free_capture();
        if(ready) $fatal(1,"release did not clear ready");
        request_capture();
        push(0); push(0); push(0);
        if(!busy || ready) $fatal(1,"auto trigger fired before its deadline");
        push(0); // Fourth valid sample forces acquisition, even in silence.
        for(i=0;i<7;i=i+1) push(0);
        if(!ready || busy || triggered) $fatal(1,"silence auto-trigger failed");
        for(i=0;i<8;i=i+1) expected[i]=0;
        check_memory();
        @(negedge clk); rst_n=0;
        @(negedge clk);
        if(ready || busy) $fatal(1,"reset left a stale capture visible");
        rst_n=1; request_capture(); push(-1); push(2);
        @(negedge clk); rst_n=0;
        @(negedge clk); rst_n=1;
        if(ready || busy) $fatal(1,"reset during capture failed");
        $display("PASS: tb_wave_capture signed samples, valid gating, trigger/fallback, freeze and reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"capture test timeout"); end
endmodule
`default_nettype wire
