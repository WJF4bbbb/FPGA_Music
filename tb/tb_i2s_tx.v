`timescale 1ns/1ps
`default_nettype none
module tb_i2s_tx;
    reg clk=0, rst_n=0;
    always #18.519 clk=~clk;
    reg signed [15:0] sample=0;
    reg sample_valid=0;
    wire bclk,lrclk,rise_ce,fall_ce,frame_load,frame_tick,data;
    wire [4:0] bit_index;
    wire [31:0] underrun_count;
    audio_timing timing (.clk(clk),.rst_n(rst_n),.bclk(bclk),.lrclk(lrclk),
        .bclk_rise_ce(rise_ce),.bclk_fall_ce(fall_ce),.bit_index(bit_index),
        .frame_load(frame_load),.frame_tick(frame_tick));
    i2s_tx dut (.clk(clk),.rst_n(rst_n),.sample(sample),.sample_valid(sample_valid),
        .bclk_fall_ce(fall_ce),.bit_index(bit_index),.frame_load(frame_load),
        .data(data),.underrun_count(underrun_count));

    reg [15:0] ref_frame=0, ref_pending=0;
    reg ref_valid=0, started=0;
    reg [31:0] ref_underruns=0;
    reg sent_bit=0, old_data, old_fall, old_rise;
    reg [4:0] old_index;
    integer cycles=0,last_load=0,loads=0,received=0,i;
    // Receiver uses WS transitions and BCLK rising samples, not bit_index.
    reg prev_ws=1, start_next=0, rx_active=0, rx_channel=0;
    reg [15:0] rx_word=0,rx_expected=0,left_word=0;
    integer rx_bits=0,rx_start=0,last_rx_start=0;
    reg [7:0] pattern_seen=0;
    function [15:0] pattern;
        input integer number;
        begin
            case(number%8)
                0:pattern=16'h0000; 1:pattern=16'h7fff;
                2:pattern=16'h8000; 3:pattern=16'hffff;
                4:pattern=16'h5555; 5:pattern=16'haaaa;
                6:pattern=16'h1234; 7:pattern=16'hfedc;
            endcase
        end
    endfunction
    task check;
        input ok;
        input [639:0] message;
        begin
            if(ok !== 1'b1) begin
                $display("FAIL cycle %0d: %0s",cycles,message);
                $finish_and_return(1); // Icarus-only nonzero failure exit.
            end
        end
    endtask

    always @(posedge clk) begin
        if(!rst_n) begin
            cycles=0; last_load=0; loads=0;
            ref_frame=0;ref_pending=0;ref_valid=0;started=0;ref_underruns=0;
            sent_bit=0;prev_ws=1;start_next=0;rx_active=0;rx_bits=0;
            last_rx_start=0;
        end else begin
            cycles=cycles+1;
            old_data=data;old_fall=fall_ce;old_rise=rise_ce;old_index=bit_index;
            if(fall_ce) sent_bit=ref_frame[15-bit_index[3:0]];
            if(frame_load) begin
                check(fall_ce && bit_index==31,"load/index contract");
                if(last_load!=0) check(cycles-last_load==576,"576 clk frame interval");
                last_load=cycles;loads=loads+1;
                if(ref_valid) ref_frame=ref_pending;
                else if(started && ref_underruns!=32'hffffffff)
                    ref_underruns=ref_underruns+1;
                started=1;ref_valid=0;
            end
            // Deliberately after consumption: same-edge result is NEXT frame.
            if(sample_valid) begin ref_pending=sample;ref_valid=1;end
            #1;
            check((^{data,underrun_count}) !== 1'bx,"no X/Z output");
            check(data===sent_bit,"serialized bit / old frame LSB / MSB order");
            if(!old_fall) check(data===old_data,"output stable except falling enable");
            check(dut.frame_sample===ref_frame,"frame sample only changes at load");
            check(underrun_count===ref_underruns,"underrun policy/count");
            if(old_rise) begin
                check(data===old_data && data===sent_bit,"receiver samples stable transmitted bit");
                if(start_next) begin
                    rx_channel=prev_ws;rx_bits=0;rx_word=0;rx_active=1;start_next=0;
                    if(!rx_channel) begin
                        rx_expected=ref_frame;rx_start=cycles;
                        if(last_rx_start!=0) check(rx_start-last_rx_start==576,"receiver full-frame period");
                        last_rx_start=rx_start;
                    end
                end
                if(rx_active) begin
                    rx_word={rx_word[14:0],data};rx_bits=rx_bits+1;
                    if(rx_bits==16) begin
                        check(rx_word===rx_expected,"receiver reconstructs signed PCM bit pattern");
                        if(!rx_channel) left_word=rx_word;
                        else begin
                            check(rx_word===left_word,"left and right identical");
                            check(cycles-rx_start==31*18,"exactly 32 sampled bits per frame");
                            received=received+1;
                            for(i=0;i<8;i=i+1) if(rx_word===pattern(i)) pattern_seen[i]=1;
                        end
                        rx_active=0;
                    end
                end
                if(lrclk!=prev_ws) begin
                    check(!rx_active,"WS transition sampled with previous channel LSB");
                    start_next=1;prev_ws=lrclk;
                end
            end
        end
    end
    task reset_dut;
        begin
            @(negedge clk); #2 rst_n=0;sample_valid=0;sample=0;
            #1;
            check(data===0 && dut.frame_sample===0 && underrun_count===0,"asynchronous reset clears output, buffers and count");
            repeat(3) @(negedge clk);
            #2 rst_n=1;
        end
    endtask
    task wait_load;
        begin
            @(posedge clk);
            while(!frame_load) @(posedge clk);
            #2;
        end
    endtask
    task submit;
        input [15:0] value;
        begin
            @(negedge clk);sample=value;sample_valid=1;
            @(negedge clk);sample_valid=0;sample=~value;
        end
    endtask
    integer j;
    initial begin
        $dumpfile("sim/i2s_tx.vcd");$dumpvars(0,tb_i2s_tx);
        reset_dut;
        wait_load;
        check(underrun_count===0 && dut.frame_sample===0,"first empty load is silent and exempt");
        for(j=0;j<112;j=j+1) begin
            submit(pattern(j));
            wait_load;
            check(dut.frame_sample===pattern(j),"submitted sample loaded");
            check(underrun_count===0,"continuous stream has no underruns");
        end
        // With an old pending result, boundary result must remain for next load.
        submit(16'h1357);
        @(negedge clk);while(!frame_load) @(negedge clk);
        sample=16'h8000;sample_valid=1;
        @(posedge clk);#2;
        check(dut.frame_sample===16'h1357,"same-edge new sample cannot bypass old pending");
        @(negedge clk);sample_valid=0;
        wait_load;
        check(dut.frame_sample===16'h8000,"same-edge sample retained for following frame");
        // Empty pending at boundary: hold last frame, count once, retain new result.
        @(negedge clk);while(!frame_load) @(negedge clk);
        sample=16'h7fff;sample_valid=1;
        @(posedge clk);#2;
        check(dut.frame_sample===16'h8000 && underrun_count===1,"empty boundary holds frame and counts underrun");
        @(negedge clk);sample_valid=0;
        wait_load;
        check(dut.frame_sample===16'h7fff && underrun_count===1,"recover from underrun");
        // Latest result wins if upstream submits twice before a load.
        submit(16'haaaa);submit(16'hfedc);wait_load;
        check(dut.frame_sample===16'hfedc,"latest pending sample wins");
        check(received>=100 && pattern_seen==8'hff,"100+ decoded frames and all required patterns");
        // Test saturation by seeding the statistic near its limit (simulation only).
        @(negedge clk);dut.underrun_count=32'hfffffffe;ref_underruns=32'hfffffffe;
        wait_load;check(underrun_count===32'hffffffff,"counter reaches maximum");
        wait_load;check(underrun_count===32'hffffffff,"counter saturates without wrap");
        // Mid-frame reset and first-load sample already available at restart.
        repeat(71) @(negedge clk);
        reset_dut;submit(16'h8001);wait_load;
        check(dut.frame_sample===16'h8001 && underrun_count===0,"first nonempty load after restart");
        submit(16'h7ffe);wait_load;
        submit(16'h0000);wait_load;
        $display("PASS: i2s_tx, %0d decoded stereo frames; boundary, underrun, saturation and reset checks",received);
        $finish;
    end
    initial begin #5000000; $display("FAIL: timeout"); $finish_and_return(1); end
endmodule
`default_nettype wire
