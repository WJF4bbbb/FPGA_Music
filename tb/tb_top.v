`timescale 1ns/1ps
`default_nettype none
// A组阶段性集成测试。下方B/C替身仅提供接口和可注入信号，不能综合。
module tb_top;
    parameter NVOICE=4;
    reg clk=0,rst_n=0,test_enable=0;
    reg [7:0] key_raw=0;
    reg timbre_key=0,bend_up_key=0,bend_down_key=0,volume_up_key=0,volume_down_key=0;
    wire bclk,lrclk,i2s_data;
    reg [15:0] injected_sample=0;
    reg [NVOICE-1:0] injected_gate=0, injected_trigger=0, injected_busy=0, injected_done=0;
    integer lane;
    integer cycle=0,core_cycle=0,last_frame=0,frame_count=0,test_events=0;
    reg [15:0] expected_frame=0,pending=0;
    reg pending_valid=0,expected_bit=0,old_fall;
    reg [10:0] held_event;
    top #(.NVOICE(NVOICE)) dut (
        .clk(clk),.rst_n(rst_n),.key_raw(key_raw),.timbre_key(timbre_key),
        .bend_up_key(bend_up_key),.bend_down_key(bend_down_key),
        .volume_up_key(volume_up_key),.volume_down_key(volume_down_key),
        .test_enable(test_enable),.bclk(bclk),.lrclk(lrclk),.i2s_data(i2s_data)
    );
    always #18.519 clk=~clk;
    task check;
        input ok;
        input [639:0] message;
        begin
            if(ok !== 1'b1) begin
                $display("FAIL top-A NVOICE=%0d cycle=%0d: %0s",NVOICE,cycle,message);
                $finish_and_return(1);
            end
        end
    endtask
    function [6:0] demo_note;
        input integer key;
        begin
            case(key) 0:demo_note=60;1:demo_note=64;2:demo_note=67;3:demo_note=72;
            default:demo_note=0;endcase
        end
    endfunction
    always @(posedge clk) begin
        cycle=cycle+1;
        if(!dut.core_rst_n) begin
            core_cycle=0;last_frame=0;frame_count=0;
            expected_frame=0;pending=0;pending_valid=0;expected_bit=0;test_events=0;
        end else begin
            core_cycle=core_cycle+1;
            check(dut.mode_locked,"core runs only after mode locked");
            check(dut.frame_load===dut.frame_tick,"shared load/tick");
            check(dut.bclk_fall_ce===((core_cycle%18)==0),"fall enable/startup");
            if(dut.bclk_fall_ce) expected_bit=expected_frame[15-dut.bit_index[3:0]];
            if(dut.frame_load) begin
                if(last_frame!=0) check(core_cycle-last_frame==576,"576 clk frame interval");
                last_frame=core_cycle;frame_count=frame_count+1;
                if(pending_valid) expected_frame=pending;
                pending_valid=0;
            end
            if(dut.mixed_valid) begin pending=dut.mixed_sample;pending_valid=1;end
            if(dut.test_mode_latched) begin
                check(dut.real_ready===0,"normal source never receives ready in test mode");
                check({dut.evt_valid,dut.evt_key,dut.evt_note,dut.evt_on}===
                      {dut.test_valid,dut.test_key,dut.test_note,dut.test_on},"entire test event routed");
                check(dut.test_ready===dut.evt_ready,"test backpressure return");
                if(dut.evt_valid && dut.evt_ready) begin
                    check(test_events<4,"only initial chord in this short test");
                    check(dut.evt_key===test_events[2:0] && dut.evt_note===demo_note(test_events) && dut.evt_on,
                          "real test_mode reaches voice_alloc input in order");
                    test_events=test_events+1;
                end
            end else begin
                check(dut.test_ready===0,"test source never receives ready in normal mode");
                check({dut.evt_valid,dut.evt_key,dut.evt_note,dut.evt_on}===
                      {dut.real_valid,dut.real_key,dut.real_note,dut.real_on},"entire normal event routed");
                check(dut.real_ready===dut.evt_ready,"normal backpressure return");
            end
            #1;
            check(bclk===(((core_cycle/9)%2)!=0),"BCLK half-period 9 clk");
            check(i2s_data===expected_bit,"sample completion -> pending -> frame -> serial bit");
            check(dut.u_i2s_tx.frame_sample===expected_frame,"load prior completed sample only");
            check((^{bclk,lrclk,i2s_data,dut.voice_note,dut.voice_valid}) !== 1'bx,"known active signals");
        end
    end
    task start_mode;
        input selected_mode;
        integer n;
        begin
            @(negedge clk);#2 rst_n=0;test_enable=selected_mode;
            #1;
            check(dut.core_rst_n===0 && bclk===0 && lrclk===1 && i2s_data===0,"async external reset reaches A chain");
            repeat(3) @(negedge clk);
            #2 rst_n=1;
            for(n=1;n<=4;n=n+1) begin
                @(posedge clk);#2;
                check(dut.core_rst_n === (n==4),"two-stage reset, mode latch, registered core release");
                if(n<4) check(bclk===0 && i2s_data===0,"no audio before startup ready");
            end
            check(dut.mode_locked && dut.test_mode_latched===selected_mode,"synchronized startup mode locked");
        end
    endtask
    task wait_frame;
        begin @(posedge clk);while(!dut.frame_load) @(posedge clk);#2;end
    endtask
    // Per-lane observability checks exercise packing with distinct injected values.
    genvar g;
    generate for(g=0;g<NVOICE;g=g+1) begin: lane_checks
        wire test_busy=injected_busy[g];
        wire test_done=injected_done[g];
        initial begin
            force dut.u_voice_alloc.voice_note[g*7 +: 7]=7'd60+g;
            force dut.voices[g].u_osc.wave=16'h1000+g;
            force dut.voices[g].u_osc.valid=1'b1;
            force dut.voices[g].u_adsr.sample=16'h8001+g;
            force dut.voices[g].u_adsr.valid=1'b1;
            force dut.voices[g].u_adsr.busy=test_busy;
            force dut.voices[g].u_adsr.env_done=test_done;
        end
        always @(negedge clk) if(dut.core_rst_n) begin
            check(dut.voices[g].u_osc.note==60+g,"distinct voice note slice");
            check(dut.voices[g].u_osc.rst_n===dut.core_rst_n && dut.voices[g].u_adsr.rst_n===dut.core_rst_n,"shared voice reset");
            check(dut.voices[g].u_osc.frame_tick===dut.frame_tick,"osc frame tick");
            check(dut.voices[g].u_adsr.frame_tick===dut.frame_tick,"adsr control snapshot tick");
            check(dut.voices[g].u_adsr.wave==16'h1000+g && dut.voices[g].u_adsr.wave_valid,"wave and valid wiring");
            check(dut.u_mixer.voice_samples[g*16 +: 16]==16'h8001+g && dut.u_mixer.voice_valid[g],"sample and valid packing");
            check(dut.voices[g].u_osc.bend===dut.bend && dut.voices[g].u_osc.timbre===dut.timbre,"signed bend/timbre route");
            check(dut.voices[g].u_adsr.gate===injected_gate[g] && dut.voices[g].u_adsr.trigger===injected_trigger[g],"gate/trigger route");
            check(dut.u_voice_alloc.voice_busy[g]===injected_busy[g] && dut.u_voice_alloc.env_done[g]===injected_done[g],"busy/env_done feedback route");
        end
    end endgenerate
    initial begin
        $dumpfile("sim/tb_top.vcd");$dumpvars(0,tb_top);
        force dut.u_voice_alloc.voice_gate=injected_gate;
        force dut.u_voice_alloc.voice_trigger=injected_trigger;
        start_mode(0);
        force dut.u_note_event.evt_valid=1'b1;
        force dut.u_note_event.evt_key_id=3'd5;
        force dut.u_note_event.evt_note=7'd69;
        force dut.u_note_event.evt_on=1'b1;
        force dut.u_voice_alloc.evt_ready=1'b0;
        force dut.u_control_panel.bend=-4'sd2;
        force dut.u_control_panel.timbre=2'd1;
        force dut.u_control_panel.master_gain=16'd32768;

        repeat(12) @(negedge clk);
        for(lane=0;lane<NVOICE;lane=lane+1) begin
            @(negedge clk);#2;
            injected_gate=1 << lane;
            injected_trigger=1 << ((lane+1)%NVOICE);
            injected_busy=1 << ((lane+2)%NVOICE);
            injected_done=1 << ((lane+3)%NVOICE);
        end
        @(negedge clk);#2;
        check(dut.evt_valid && dut.evt_key==5 && dut.evt_note==69 && !dut.real_ready,"normal event/backpressure path");
        check(dut.u_mixer.master_gain==32768 && dut.u_mixer.frame_tick===dut.frame_tick,"mixer gain/tick route");
        test_enable=1;
        repeat(12) @(negedge clk);
        check(dut.test_mode_latched===0,"runtime external mode change ignored");
        release dut.u_voice_alloc.evt_ready;
        // Inject a completed mixer sample; this is wiring stimulus, not synthesis.
        force dut.u_mixer.sample=injected_sample;
        force dut.u_mixer.valid=1'b0;
        wait_frame;
        @(negedge clk);injected_sample=16'h8001;force dut.u_mixer.valid=1'b1;
        @(negedge clk);force dut.u_mixer.valid=1'b0;
        wait_frame;check(dut.u_i2s_tx.frame_sample===16'h8001,"first injected signed sample loaded");
        @(negedge clk);injected_sample=16'h7ffe;force dut.u_mixer.valid=1'b1;
        @(negedge clk);force dut.u_mixer.valid=1'b0;
        wait_frame;check(dut.u_i2s_tx.frame_sample===16'h7ffe,"second injected sample loaded without tearing");
        wait_frame;
        check(dut.underrun_count!=0,"missing mixer result visible as underrun");
        release dut.u_mixer.sample;release dut.u_mixer.valid;
        release dut.u_note_event.evt_valid;release dut.u_note_event.evt_key_id;
        release dut.u_note_event.evt_note;release dut.u_note_event.evt_on;
        start_mode(1);
        force dut.u_voice_alloc.evt_ready=1'b0;
        repeat(15) @(negedge clk);
        held_event={dut.test_key,dut.test_note,dut.test_on};
        check(dut.test_valid && test_events==0,"demo waits for downstream ready");
        test_enable=0;
        repeat(17) begin
            @(negedge clk);
            check(dut.test_mode_latched && dut.test_valid && {dut.test_key,dut.test_note,dut.test_on}===held_event,
                  "latched mode and event survive runtime mode toggle under stall");
        end
        release dut.u_voice_alloc.evt_ready;
        repeat(10) @(negedge clk);
        check(test_events==4,"four actual test_mode events delivered to allocator interface");
        wait_frame;wait_frame;
        force dut.u_voice_alloc.voice_gate=injected_gate;
        force dut.u_voice_alloc.voice_trigger=injected_trigger;
        start_mode(0);repeat(12) @(negedge clk);
        check(test_events==0 && !dut.test_mode_latched,"shared reset safely restarts normal mode");
        $display("PASS: top A-only integration NVOICE=%0d; B/C are test-only interface substitutes",NVOICE);
        $finish;
    end
    initial begin #1000000;$display("FAIL: timeout");$finish_and_return(1);end
endmodule

// B/C接口替身：只用于上述接线测试，绝不能加入正式源列表。
module sensor_frontend(input wire clk,rst_n,input wire [7:0] key_raw,output wire [7:0] key_state);
    assign key_state=8'd0;
endmodule
module control_panel(input wire clk,rst_n,timbre_key,bend_up_key,bend_down_key,volume_up_key,volume_down_key,
    output wire [1:0] timbre,output wire signed [3:0] bend,output wire [15:0] master_gain);
    assign timbre=0;assign bend=0;assign master_gain=16384;
endmodule
module note_event(input wire clk,rst_n,input wire [7:0] key_state,input wire evt_ready,
    output wire evt_valid,output wire [2:0] evt_key_id,output wire [6:0] evt_note,output wire evt_on,output wire [31:0] overflow_count);
    assign evt_valid=0;assign evt_key_id=0;assign evt_note=0;assign evt_on=0;assign overflow_count=0;
endmodule
module voice_alloc #(parameter NVOICE=4)(input wire clk,rst_n,evt_valid,output wire evt_ready,
    input wire [2:0] evt_key_id,input wire [6:0] evt_note,input wire evt_on,input wire [NVOICE-1:0] voice_busy,env_done,
    output wire [NVOICE*7-1:0] voice_note,output wire [NVOICE-1:0] voice_gate,voice_trigger);
    assign evt_ready=1;assign voice_note={NVOICE{7'd60}};assign voice_gate=0;assign voice_trigger=0;
endmodule
module osc #(parameter FS_HZ=46875)(input wire clk,rst_n,frame_tick,input wire [6:0] note,
    input wire [1:0] timbre,input wire signed [3:0] bend,output wire signed [15:0] wave,output wire valid);
    assign wave=0;assign valid=0;
endmodule
module adsr #(parameter FS_HZ=46875)(input wire clk,rst_n,frame_tick,wave_valid,input wire signed [15:0] wave,
    input wire gate,trigger,output wire signed [15:0] sample,output wire valid,busy,env_done);
    assign sample=0;assign valid=0;assign busy=0;assign env_done=0;
endmodule
module mixer #(parameter NVOICE=4)(input wire clk,rst_n,frame_tick,input wire [NVOICE*16-1:0] voice_samples,
    input wire [NVOICE-1:0] voice_valid,input wire [15:0] master_gain,
    output wire signed [15:0] sample,output wire valid,output wire [31:0] clip_count);
    assign sample=0;assign valid=0;assign clip_count=0;
endmodule
`default_nettype wire
