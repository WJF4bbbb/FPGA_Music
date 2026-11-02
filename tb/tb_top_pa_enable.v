`timescale 1ns/1ps
`default_nettype none
// External-pin decoder checks startup ordering without reading DUT warmup state.
module tb_top_pa_enable;
    reg clk=0, rst_n=0, test_enable=1;
    wire ttp_scl,ttp_sdo;
    ttp229_model chip(.rst_n(rst_n),.scl(ttp_scl),.keys(16'd0),.sdo(ttp_sdo));
    wire bclk, lrclk, i2s_data, pa_en;
    top dut (.*);
    always #18.518518518 clk=~clk;
    integer cycle=0, last_bclk_edge=0, frames=0, muted_frames=0, audible_frames=0;
    integer bits=0, enables=0, resets=0, i;
    reg previous_ws=1, start_next=0, active=0, channel=0, have_left=0;
    reg [15:0] word_bits=0, left_word=0;
    reg [15:0] previous_left=0;
    reg enabled_previous=0;
    always @(posedge clk) cycle=cycle+1;
    task check(input bit ok, input string message);
        if (ok !== 1'b1) begin
            $display("FAIL PA: cycle=%0d %s",cycle,message);
            $finish_and_return(1);
        end
    endtask
    task cycles(input integer n);
        repeat(n) @(negedge clk);
    endtask
    always @(bclk) begin
        if(rst_n && dut.core_rst_n) begin
            if(last_bclk_edge!=0) check(cycle-last_bclk_edge==9,"BCLK half period stays nine clocks");
            last_bclk_edge=cycle;
        end else last_bclk_edge=0;
    end
    always @(negedge rst_n) begin
        frames=0;muted_frames=0;audible_frames=0;bits=0;
        previous_ws=1;start_next=0;active=0;have_left=0;last_bclk_edge=0;
    end
    always @(posedge bclk) begin
        #1;
        if(rst_n) begin
            if(!pa_en) check(i2s_data===0,"serial data is zero throughout warmup");
            if(start_next) begin
                check(!active,"no truncated channel");
                start_next=0;active=1;bits=1;word_bits={15'd0,i2s_data};channel=lrclk;
            end else if(active) begin
                word_bits={word_bits[14:0],i2s_data};bits=bits+1;
                if(bits==16) begin
                    active=0;
                    if(!channel) begin left_word=word_bits;have_left=1;end
                    else begin
                        check(have_left,"right word follows complete left word");
                        check(word_bits===left_word,"complete stereo words agree");
                        frames=frames+1;have_left=0;
                        if(!pa_en) begin
                            check(word_bits===0,"complete muted stereo frame is silent");
                            muted_frames=muted_frames+1;
                        end else if(word_bits!=0) audible_frames=audible_frames+1;
                    end
                end
            end
            if(lrclk!=previous_ws) begin
                check(!active,"WS changes at old channel LSB");
                start_next=1;previous_ws=lrclk;
            end
        end
    end
    always @(posedge pa_en) begin
        #1;
        check(rst_n===1 && muted_frames>=2,"PA only rises after two decoded silent stereo frames");
        check(bclk===0 && lrclk===0,"PA rises on the first left-MSB falling edge");
        enables=enables+1;
    end
    initial begin
        cycles(4);check(pa_en===0,"external reset holds amplifier off");
        rst_n=1;
        wait(pa_en===1);cycles(36*576);
        check(audible_frames>0,"real demo becomes audible after enabling");
        // Reset at three distinct bit phases, including when BCLK is high.
        for(i=0;i<3;i=i+1) begin
            cycles(7+i*9);#2 rst_n=0;#1;
            check(pa_en===0,"reset asynchronously turns PA off between clock edges");
            cycles(4);rst_n=1;wait(pa_en===1);cycles(3*576);resets=resets+1;
        end
        rst_n=0;test_enable=0;cycles(4);rst_n=1;
        wait(pa_en===1);cycles(10*576);
        check(audible_frames==0,"normal idle serial stream remains silent");
        check(pa_en===1,"PA remains enabled on continuous silent stream");
        check(enables==5 && resets==3,"all startup/reset sequences exercised");
        $display("PASS: tb_top_pa_enable all checks passed; startup sequences=%0d",enables);$finish;
    end
    initial begin #3000000;$display("FAIL PA: timeout");$finish_and_return(1);end
endmodule
`default_nettype wire
