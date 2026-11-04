// This .v testbench uses SystemVerilog; keep IDE keyword parsing consistent with -g2012.
`begin_keywords "1800-2012"
`timescale 1ns/1ps
`default_nettype none
// Real A+B+C system. Only external pins are driven; hierarchy is read-only.
module tb_top_integration;
    reg clk=0, rst_n=0, test_enable=0;
    reg [7:0] key_raw=0;
    reg timbre_key=0, bend_up_key=0, bend_down_key=0;
    reg volume_up_key=0, volume_down_key=0;
    wire bclk, lrclk, i2s_data, pa_en,ttp_scl,ttp_sdo;
    // Logical test stimuli go through the external BSF serial model.
    wire [15:0] touch_bitmap={3'd0,bend_down_key,bend_up_key,volume_down_key,volume_up_key,timbre_key,key_raw};
    ttp229_model chip(.rst_n(rst_n),.scl(ttp_scl),.keys(touch_bitmap),.sdo(ttp_sdo));
    localparam integer FRAME=576, SENSOR=5400, CONTROL=135000;
    localparam integer CTRL_WAIT=CONTROL+2+1, BUDGET=270000, ACQUIRE_BOUND=89378;
    // At worst: debounce+sync; two phase ticks before changed phase output;
    // <=128 pipeline clocks; one pending/load frame; <=36 clocks to left MSB.
    localparam integer CONTROL_BOUND=ACQUIRE_BOUND+CTRL_WAIT+3*FRAME+128+36;
    top #(.NVOICE(4),.TTP_STARTUP_CYCLES(270),.DEMO_ENABLE(1)) dut (
        .clk(clk),.rst_n(rst_n),.test_enable(test_enable),.ttp_scl(ttp_scl),.ttp_sdo(ttp_sdo),
        .bclk(bclk),.lrclk(lrclk),.i2s_data(i2s_data),.pa_en(pa_en)
    );
    // Only startup wait/demo duration are accelerated. Formal SCL/gap and filters stay real-time.
    defparam dut.u_test_mode.HOLD_FRAMES=128;
    defparam dut.u_test_mode.RELEASE_FRAMES=128;
    always #18.518518518 clk=~clk;

    integer cycle=0, assertions=0, frames=0, decoded=0, total_decoded=0;
    integer events=0, demo_events=0, failures=0, pcm_frames=0;
    integer frame_cycle=0, last_frame=0, max_pipeline=0;
    integer i, sel, oldest, qread=0, qwrite=0, eqread=0, eqwrite=0;
    integer stamp=0, model_stamp[0:3], model_key[0:3];
    reg [3:0] model_gate=0, model_owned=0;
    reg [6:0] model_note[0:3];
    reg [7:0] previous_keys=0;
    reg [10:0] expected_events[0:4095];
    reg [15:0] expected_frames[0:32767];
    integer production_cycles[0:32767];
    bit control_frames[0:32767];
    reg [15:0] pending_pcm=0, gain_snapshot=0;
    integer pending_cycle=0;
    integer last_pcm_cycle=0, control_pcm=-1, control_ticks=0, control_guard;
    bit pending_control=0, last_pcm_control=0, frame_control=0, measure_control=0;
    reg pending=0, loaded=0, stalled=0;
    reg [10:0] stalled_payload;
    reg [3:0] pre_valid, expected_trigger;
    reg [15:0] pre_gain;
    reg [63:0] pre_samples;
    reg pre_tick, pre_mixed_valid;
    reg signed [15:0] pre_mixed;
    reg [3:0] pre_done;
    reg [31:0] phase_bus[0:3];
    wire signed [15:0] waves[0:3], levels[0:3];
    wire [3:0] osc_valid;
    integer lane_waves[0:3], lane_samples[0:3], contributions[0:3];
    integer min_wave[0:3], max_wave[0:3];
    integer signed sum, expected_mix, lane, omitted;
    reg signed [63:0] product;
    integer raw_cycle=-1, event_cycle=-1, alloc_cycle=-1, pcm_cycle=-1, serial_cycle=-1;
    reg measure_latency=0;
    integer control_start, control_commit, control_apply, control_serial, saved_events, saved_trigger;
    integer reader_commit_cycle=-1;
    integer triggers[0:3];
    reg [3:0] saved_gates;
    integer waveform_frames=0;
    integer envelope_states[0:3];
    string phase_name="startup";

    task check(input bit ok, input string message);
        assertions=assertions+1;
        if (!ok) begin
            $display("FAIL [%s] cycle=%0d t=%0t: %s",phase_name,cycle,$time,message);
            $finish_and_return(1);
        end
    endtask
    function automatic integer midi(input integer k);
        case(k)
            0:midi=60;1:midi=62;2:midi=64;3:midi=65;
            4:midi=67;5:midi=69;6:midi=71;7:midi=72;
        endcase
    endfunction
    function automatic integer demo_note(input integer k);
        case(k) 0:demo_note=60;1:demo_note=64;2:demo_note=67;3:demo_note=72; endcase
    endfunction
    task cycles(input integer n);
        repeat(n) @(negedge clk);
        #1;
    endtask
    task audio_frames(input integer n);
        integer target;
        begin
            target=frames+n;
            while(frames<target) cycles(1);
        end
    endtask
    task boot(input bit demo);
        begin
            @(negedge clk); #1;
            rst_n=0; test_enable=demo; key_raw=0;
            timbre_key=0; bend_up_key=0; bend_down_key=0;
            volume_up_key=0; volume_down_key=0;
            cycles(4);
            check({bclk,lrclk,i2s_data}===3'b010,"asynchronous reset pins expected=010");
            check(dut.voice_gate===0 && dut.voice_busy===0 && dut.mixed_sample===0,
                  "reset gates/busy/PCM expected=0");
            check(dut.timbre===0 && dut.bend===0 && dut.master_gain===16384,
                  "reset configuration expected timbre=0 bend=0 gain=16384");
            check(dut.u_control_panel.CTRL_FILT==CONTROL,
                  $sformatf("formal default CTRL_FILT actual=%0d expected=%0d; no TB filter override",
                            dut.u_control_panel.CTRL_FILT,CONTROL));
            rst_n=1;
            cycles(3); check(dut.core_rst_n===0,"core reset must remain asserted through mode lock");
            cycles(1); check(dut.core_rst_n===1,"core reset released on fourth clock");
            check(dut.test_mode_latched===demo,"startup mode latch");
            cycles(4);
        end
    endtask
    task keys(input [7:0] value);
        integer guard;
        begin
            key_raw=value;guard=0;
            while((!dut.touch_valid || dut.touch_keys[7:0]!==value) && guard<=ACQUIRE_BOUND) begin
                cycles(1);guard=guard+1;
            end
            check(guard<=ACQUIRE_BOUND,"external note bitmap acquired within serial polling bound");
            if(measure_latency && reader_commit_cycle<0) reader_commit_cycle=cycle;
            cycles(SENSOR+2+1+8);
            check(dut.key_state===value,$sformatf("sensor expected=%h actual=%h",value,dut.key_state));
            check(eqread==eqwrite,"all expected key events consumed exactly once");
        end
    endtask
    task quiet;
        integer guard;
        begin
            guard=0;
            while(dut.voice_busy!==0 && guard<7100) begin audio_frames(16); guard=guard+16; end
            check(dut.voice_busy===0,"release finishes within ceil(32767/5) frames");
            audio_frames(3);
            check(dut.voice_gate===0 && dut.voice_samples===0 && dut.mixed_sample===0,
                  "release produces exact silence and no residual gate");
        end
    endtask

    // Event ordering, independent allocation model, PCM reference, TX queue.
    // Read pre-edge handshake data, then check registered results after NBA.
    always @(posedge clk) begin
        cycle=cycle+1;
        if (dut.core_rst_n !== 1'b1) begin
            frames=0; last_frame=0; frame_cycle=0; pcm_frames=0;
            model_gate=0; model_owned=0; stamp=0; previous_keys=0;
            qread=0;qwrite=0;eqread=0;eqwrite=0;pending=0;loaded=0;gain_snapshot=0;
            events=0;demo_events=0;stalled=0;last_pcm_cycle=0;
            pending_control=0;last_pcm_control=0;frame_control=0;control_ticks=0;
            for(i=0;i<4;i=i+1) begin
                model_note[i]=60; model_key[i]=0; model_stamp[i]=0; triggers[i]=0;
                contributions[i]=0;
            end
        end else if(dut.frame_tick || (|dut.voice_valid) || dut.mixed_valid || dut.evt_valid ||
                    dut.real_valid || dut.key_state!=previous_keys || (|dut.env_done)) begin
            pre_tick=dut.frame_tick; pre_valid=dut.voice_valid;
            pre_samples=dut.voice_samples;pre_gain=gain_snapshot;
            pre_mixed_valid=dut.mixed_valid;pre_mixed=dut.mixed_sample;pre_done=dut.env_done;
            expected_trigger=0;sel=-1;
            check(dut.frame_tick===dut.frame_load,"frame_tick equals frame_load");
            check(pre_valid===0 || pre_valid===4'b1111,$sformatf("aligned lane valid actual=%b",pre_valid));
            if (dut.test_mode_latched) begin
                check(dut.real_ready===0 && dut.test_ready===dut.evt_ready,"demo exclusively selected");
            end else check(dut.test_ready===0 && dut.real_ready===dut.evt_ready,"normal exclusively selected");
            if (stalled) check(dut.real_valid && {dut.real_key,dut.real_note,dut.real_on}===stalled_payload,
                               "unselected/backpressured real source keeps entire event");
            stalled=dut.real_valid && !dut.real_ready;
            stalled_payload={dut.real_key,dut.real_note,dut.real_on};

            if (dut.evt_valid && dut.evt_ready) begin
                events=events+1;
                if (dut.test_mode_latched) begin
                    check(dut.evt_key==demo_events%4 && dut.evt_note==demo_note(demo_events%4) &&
                          dut.evt_on==(demo_events%8<4),"demo event order/note/on fields");
                    demo_events=demo_events+1;
                end else begin
                    check(eqread<eqwrite,"no unsolicited or duplicate real event");
                    check({dut.evt_key,dut.evt_note,dut.evt_on}===expected_events[eqread],
                          $sformatf("FIFO event index=%0d actual=%h expected=%h",eqread,
                          {dut.evt_key,dut.evt_note,dut.evt_on},expected_events[eqread]));
                    eqread=eqread+1;
                end
                if (measure_latency && dut.evt_on && event_cycle<0) begin
                    event_cycle=cycle;alloc_cycle=cycle;
                end
                if (dut.evt_on) begin
                    for(i=0;i<4;i=i+1)
                        if(sel<0 && model_owned[i] && model_key[i]==dut.evt_key) sel=i;
                    for(i=0;i<4;i=i+1)
                        if(sel<0 && !model_gate[i] && !dut.voice_busy[i]) sel=i;
                    if(sel<0) begin
                        oldest=32'h7fffffff;
                        for(i=0;i<4;i=i+1) if(!model_gate[i] && model_stamp[i]<oldest) begin
                            oldest=model_stamp[i];sel=i;
                        end
                    end
                    if(sel<0) begin
                        oldest=32'h7fffffff;
                        for(i=0;i<4;i=i+1) if(model_stamp[i]<oldest) begin oldest=model_stamp[i];sel=i;end
                    end
                    check(sel>=0,"note_on selects a voice");
                    model_gate[sel]=1;model_owned[sel]=1;model_key[sel]=dut.evt_key;
                    model_note[sel]=dut.evt_note;model_stamp[sel]=stamp;expected_trigger[sel]=1;
                end else for(i=0;i<4;i=i+1)
                    if(model_owned[i] && model_key[i]==dut.evt_key) model_gate[i]=0;
                stamp=stamp+1;
            end
            for(i=0;i<4;i=i+1) if(pre_done[i] && i!=sel) model_owned[i]=0;
            // FIFO contract: batch releases first, then presses, each in key order.
            for(i=0;i<8;i=i+1) if(previous_keys[i] && !dut.key_state[i]) begin
                expected_events[eqwrite]={i[2:0],7'(midi(i)),1'b0};eqwrite=eqwrite+1;
            end
            for(i=0;i<8;i=i+1) if(!previous_keys[i] && dut.key_state[i]) begin
                expected_events[eqwrite]={i[2:0],7'(midi(i)),1'b1};eqwrite=eqwrite+1;
            end
            previous_keys=dut.key_state;
            check(eqwrite<4096,"event scoreboard capacity");
            if(pre_tick) begin
                if(last_frame>0) check(cycle-last_frame==FRAME,"576 system clocks per audio frame");
                last_frame=cycle;frame_cycle=cycle;frames=frames+1;
                gain_snapshot=dut.master_gain;
                if(measure_control && dut.bend==2) control_ticks=control_ticks+1;
                else control_ticks=0;
                // First changed FCW advances phase; next tick emits that changed phase.
                frame_control=measure_control && control_ticks>=2;
                check(!loaded || pending,"PCM ready before every load after startup");
                check(qwrite<32768,"I2S scoreboard capacity");
                expected_frames[qwrite]=pending ? pending_pcm : 0;
                production_cycles[qwrite]=pending ? pending_cycle : 0;
                control_frames[qwrite]=pending && pending_control;
                qwrite=qwrite+1;pending=0;loaded=1;
            end
            if(pre_mixed_valid) begin
                pending_pcm=pa_en ? pre_mixed : 16'd0;pending_cycle=last_pcm_cycle;pending=1;
                pending_control=last_pcm_control;
            end
            sum=0;
            for(i=0;i<4;i=i+1) sum=sum+$signed(pre_samples[i*16+:16]);
            product=(sum>>>2)*$signed({1'b0,pre_gain});
            expected_mix=product>>>16;
            if(expected_mix>32767) expected_mix=32767;
            if(expected_mix< -32768) expected_mix=-32768;
            #1;
            check(dut.voice_gate===model_gate,$sformatf("allocation gates actual=%b expected=%b",dut.voice_gate,model_gate));
            check(dut.voice_trigger===expected_trigger,"one clock trigger on selected voice only");
            for(i=0;i<4;i=i+1) begin
                check(dut.voice_note[i*7+:7]===model_note[i],"packed note slice matches independent allocation");
                if(dut.voice_trigger[i]) triggers[i]=triggers[i]+1;
            end
            check(dut.mixed_valid==(&pre_valid),"exactly one mixed valid for complete lane sample set");
            if(&pre_valid) begin
                check(dut.mixed_sample===16'(expected_mix),
                      $sformatf("signed mix actual=%0d expected=%0d sum=%0d gain=%0d",dut.mixed_sample,expected_mix,sum,pre_gain));
                pcm_frames=pcm_frames+1;
                last_pcm_cycle=cycle;last_pcm_control=frame_control;
                if(frame_control && control_pcm<0) control_pcm=cycle;
                if(cycle-frame_cycle>max_pipeline) max_pipeline=cycle-frame_cycle;
                check(cycle-frame_cycle<=128,"frame to PCM pipeline <=128 clocks");
                for(i=0;i<4;i=i+1) begin
                    product=((sum-$signed(pre_samples[i*16+:16]))>>>2)*$signed({1'b0,pre_gain});
                    omitted=product>>>16;
                    if(omitted!=expected_mix) contributions[i]=contributions[i]+1;
                end
                if(measure_latency && event_cycle>=0 && pcm_cycle<0 && dut.mixed_sample!=0) pcm_cycle=cycle;
            end
            check(dut.underrun_count===0 && dut.overflow_count===0 && dut.clip_count===0,
                  "normal operation underrun/overflow/clip counters all zero");
        end
    end

    genvar g;
    generate for(g=0;g<4;g=g+1) begin: observe
        assign waves[g]=dut.voices[g].wave;
        assign levels[g]=dut.voices[g].u_adsr.level;
        assign osc_valid[g]=dut.voices[g].wave_valid;
        reg [31:0] old_phase;
        reg [31:0] held_phase=0;
        reg tick, wvalid;
        reg signed [15:0] wave_before;
        reg signed [63:0] env_product;
        integer expected_wave, delta, target_delta;
        real frequency, ratio;
        integer golden_level=0, golden_state=0;
        bit trigger_pending=0, trigger_snapshot=0, gate_snapshot=0, golden_done;
        always @(posedge clk) begin
            if(dut.core_rst_n !== 1'b1) begin
                lane_waves[g]=0;lane_samples[g]=0;min_wave[g]=32767;max_wave[g]=-32768;
                golden_level=0;golden_state=0;trigger_pending=0;
                held_phase=0;
                trigger_snapshot=0;gate_snapshot=0;envelope_states[g]=1;
            end else begin
                if(dut.frame_tick) begin
                    trigger_snapshot=trigger_pending || dut.voice_trigger[g];
                    gate_snapshot=dut.voice_gate[g];trigger_pending=0;
                end else if(dut.voice_trigger[g]) trigger_pending=1;
                if(dut.frame_tick || osc_valid[g]) begin
                old_phase=dut.voices[g].u_osc.phase;
                tick=dut.frame_tick;wvalid=osc_valid[g];wave_before=waves[g];
                frequency=440.0*(2.0**(($itor(dut.voice_note[g*7+:7])-69.0)/12.0));
                case(dut.bend) 2:ratio=73562.0/65536.0; -2:ratio=58385.0/65536.0; default:ratio=1.0; endcase
                target_delta=$rtoi(frequency*4294967296.0/46875.0*ratio);
                if(dut.timbre==0)
                    expected_wave=$rtoi(32767.0*$sin(6.283185307179586*old_phase[31:24]/256.0)+
                                       (old_phase[31] ? -0.5 : 0.5));
                else expected_wave=old_phase[31] ? -32768 : 32767;
                golden_done=0;
                if(wvalid) begin
                    if(trigger_snapshot) begin
                        golden_level=(golden_level>32767-71) ? 32767 : golden_level+71;
                        golden_state=1;
                    end else if(golden_state!=0 && !gate_snapshot) begin
                        if(golden_level<=5) begin golden_level=0;golden_state=0;golden_done=1;end
                        else begin golden_level=golden_level-5;golden_state=4;end
                    end else case(golden_state)
                        0:golden_level=0;
                        1:if(golden_level>32767-71) begin golden_level=32767;golden_state=2;end
                          else golden_level=golden_level+71;
                        2:if(golden_level<19660+2) begin golden_level=19660;golden_state=3;end
                          else golden_level=golden_level-2;
                        3:golden_level=19660;
                        4:if(golden_level<=5) begin golden_level=0;golden_state=0;golden_done=1;end
                          else golden_level=golden_level-5;
                    endcase
                    trigger_snapshot=0;
                    envelope_states[g]=envelope_states[g] | (1<<golden_state);
                end
                #1;
                check(osc_valid[g]===tick,$sformatf("lane %0d oscillator valid latency",g));
                if(tick) begin
                    delta=dut.voices[g].u_osc.phase-old_phase;
                    // FCW table rounds note frequencies; <=0.01% permits its documented rounding.
                    check(delta>0 && $abs(delta-target_delta)<target_delta/10000,
                          $sformatf("lane %0d DDS step actual=%0d mathematical=%0d",g,delta,target_delta));
                    held_phase=dut.voices[g].u_osc.phase;
                    check($abs($signed(waves[g])-expected_wave)<=1,
                          $sformatf("lane %0d waveform actual=%0d expected=%0d",g,waves[g],expected_wave));
                    if(waves[g]!=0) lane_waves[g]=lane_waves[g]+1;
                    if(waves[g]<min_wave[g]) min_wave[g]=waves[g];
                    if(waves[g]>max_wave[g]) max_wave[g]=waves[g];
                end else check(dut.voices[g].u_osc.phase===old_phase,"DDS phase holds between frames");
                check(dut.voice_valid[g]===wvalid,"ADSR valid follows oscillator by one clock");
                if(wvalid) begin
                    check(levels[g]==golden_level && dut.env_done[g]===golden_done,
                          $sformatf("lane %0d envelope trajectory actual=%0d expected=%0d done=%b/%b",g,levels[g],golden_level,dut.env_done[g],golden_done));
                    env_product=wave_before*golden_level;
                    check(dut.voice_samples[g*16+:16]===16'(env_product>>>15),
                          $sformatf("lane %0d envelope multiplication",g));
                    if($signed(dut.voice_samples[g*16+:16])!=0) lane_samples[g]=lane_samples[g]+1;
                end
                end
            end
        end
        // Check EVERY phase change, including changes between frame ticks.
        // Retain the verified reference and wait past the tick oracle's #1.
        // Event-based checking avoids millions of identical idle assertions.
        always @(dut.voices[g].u_osc.phase) begin
            #2;
            if(dut.core_rst_n===1'b1 && rst_n===1'b1 &&
               dut.voices[g].u_osc.phase!==held_phase)
                check(0,$sformatf("lane %0d phase changed between ticks: actual=%h held=%h",g,
                                  dut.voices[g].u_osc.phase,held_phase));
        end
    end endgenerate

    // Independent Philips I2S receiver. No DUT bit_index/frame_sample is used.
    reg previous_ws=1, start_next=0, rx_active=0, rx_channel=0, left_valid=0;
    reg [15:0] rx_word=0, left_word=0;
    integer bits=0, left_start=0, last_bclk_rise=0, last_ws_rise=0;
    integer last_bclk_edge=0, last_data_change=0;
    always @(bclk or negedge rst_n) begin
        if(!rst_n) last_bclk_edge=0;
        else begin
            if(last_bclk_edge>0) check(cycle-last_bclk_edge==9,"BCLK high and low each exactly 9 clocks");
            last_bclk_edge=cycle;
        end
    end
    always @(i2s_data) last_data_change=cycle;
    always @(posedge bclk or negedge rst_n) begin
        if(!rst_n) begin
            decoded=0;bits=0;previous_ws=1;start_next=0;rx_active=0;left_valid=0;
            last_bclk_rise=0;last_ws_rise=0;rx_word=0;left_word=0;
        end else begin
            if(last_bclk_rise>0) check(cycle-last_bclk_rise==18,"BCLK rising edges 18 clocks apart");
            last_bclk_rise=cycle;
            check((^{lrclk,i2s_data})!==1'bx,"known external I2S pins");
            check(cycle-last_data_change>=9,"I2S data stable for half BCLK before receiver edge");
            if(start_next) begin
                rx_channel=previous_ws;rx_word=0;bits=0;rx_active=1;start_next=0;
                if(!rx_channel) left_start=cycle;
            end
            if(rx_active) begin
                rx_word={rx_word[14:0],i2s_data};bits=bits+1;
                if(bits==16) begin
                    rx_active=0;
                    check(qread<qwrite,"receiver has a produced expected PCM frame");
                    check(rx_word===expected_frames[qread],
                          $sformatf("I2S frame=%0d channel=%0d actual=%h expected PCM=%h",decoded,rx_channel,rx_word,expected_frames[qread]));
                    if(!rx_channel) begin
                        left_word=rx_word;left_valid=1;
                        if(measure_latency && pcm_cycle>=0 && serial_cycle<0 && rx_word!=0) serial_cycle=left_start;
                        if(measure_control && control_frames[qread] && control_serial<0) begin
                            control_serial=left_start;
                            check(production_cycles[qread]>=control_pcm,"changed-control PCM provenance precedes verified serial frame");
                        end
                    end else begin
                        check(left_valid && left_word===rx_word,"stereo pair complete and identical");
                        left_valid=0;qread=qread+1;decoded=decoded+1;total_decoded=total_decoded+1;
                    end
                end
            end
            if(lrclk!=previous_ws) begin
                check(!rx_active,"WS changes with prior channel LSB; next edge is new MSB");
                if(last_ws_rise>0) check(cycle-last_ws_rise==16*18,"16 bits per channel");
                last_ws_rise=cycle;start_next=1;previous_ws=lrclk;
            end
        end
    end

    task panel_check(input integer kind, input integer expected);
        begin
            cycles(ACQUIRE_BOUND+CTRL_WAIT);
            case(kind)
                0:check(dut.timbre==expected,"timbre press/release");
                1:check($signed(dut.bend)==expected,$sformatf("bend actual=%0d expected=%0d",dut.bend,expected));
                2:check(dut.master_gain==expected,"volume press/release");
            endcase
            audio_frames(2); // lane/mix reference and external decoder validate propagated configuration
        end
    endtask
    initial begin
        $dumpfile("sim/tb_top_integration.vcd");
        // Deliberately omit 27MHz clk and debounce counters to keep full-default VCD usable.
        $dumpvars(0,rst_n,test_enable,key_raw,timbre_key,bend_up_key,bend_down_key,
                  volume_up_key,volume_down_key,bclk,lrclk,i2s_data,pa_en,dut.core_rst_n,
                  dut.key_state,dut.evt_valid,dut.evt_ready,dut.evt_key,dut.evt_note,dut.evt_on,
                  dut.voice_note,dut.voice_gate,dut.voice_trigger,dut.voice_busy,dut.env_done,
                  dut.voice_samples,dut.voice_valid,dut.mixed_sample,dut.mixed_valid,
                  dut.master_gain,dut.bend,dut.timbre);
        phase_name="A reset/startup";boot(1);
        $display("PASS [A] reset/startup; shared reset and demo latch");
        phase_name="B real four-voice demo";
        test_enable=0;key_raw=8'hff;
        audio_frames(96);
        check(dut.test_mode_latched===1 && dut.voice_gate===4'b1111,"live mode input cannot switch locked demo");
        check(demo_events==4,"exactly four demo note_on handshakes before hold expires");
        for(lane=0;lane<4;lane=lane+1) begin
            check(lane_waves[lane]>32 && lane_samples[lane]>32 && contributions[lane]>32,
                  $sformatf("lane %0d independently oscillates, envelopes and contributes to PCM",lane));
            check(min_wave[lane]<0 && max_wave[lane]>0,"each demo wave spans both polarities");
            $display("VOICE lane=%0d note=%0d wave_nonzero=%0d envelope_nonzero=%0d mix_contributions=%0d",
                     lane,dut.voice_note[lane*7+:7],lane_waves[lane],lane_samples[lane],contributions[lane]);
        end
        audio_frames(48);check(demo_events==8 && dut.voice_gate===0,"four demo note_off events release all gates");
        $display("PASS [B] four real voices, independent signed mix and demo releases");

        phase_name="C raw sensor/event/voice path";boot(0);
        test_enable=1;cycles(5);check(dut.test_mode_latched===0,"normal mode also remains locked");
        measure_latency=1;raw_cycle=cycle;
        keys(8'h01);check(dut.voice_gate===1,"single real key gets voice zero");
        audio_frames(32);
        check(event_cycle>=0 && pcm_cycle>=0 && serial_cycle>=0,"all key latency measurement endpoints observed");
        $display("LATENCY key raw_event=%0d event_alloc=%0d alloc_pcm=%0d pcm_i2s_msb=%0d total=%0d clocks (%0.6f ms)",
                 event_cycle-raw_cycle,alloc_cycle-event_cycle,pcm_cycle-alloc_cycle,serial_cycle-pcm_cycle,
                 serial_cycle-raw_cycle,(serial_cycle-raw_cycle)/27000.0);
        check(serial_cycle-raw_cycle<=BUDGET,"raw note input to first verified nonzero I2S MSB <=10ms");
        $display("LATENCY serial_note A_input_commit=%0d B_commit_i2s=%0d C_input_i2s=%0d clocks",
                 reader_commit_cycle-raw_cycle,serial_cycle-reader_commit_cycle,serial_cycle-raw_cycle);
        measure_latency=0;keys(0);quiet;
        keys(8'h03);check(dut.voice_gate===4'b0011,"two simultaneous keys");
        keys(8'h0f);check(dut.voice_gate===4'b1111,"four simultaneous keys");
        audio_frames(24);
        keys(8'h1f);check(dut.voice_note[0+:7]===7'd67,"fifth key steals oldest held key zero");
        saved_gates=dut.voice_gate;keys(8'h1e);check(dut.voice_gate===saved_gates,"stolen key release is harmless");
        keys(8'h1a);keys(8'h3a);check(dut.voice_note[14+:7]===7'd69,"release-tail lane is stolen before held lanes");
        saved_trigger=triggers[2];keys(8'h1a);keys(8'h3a);
        check(triggers[2]==saved_trigger+1,"same physical key retriggers its existing voice once");
        wait(dut.touch_commit);cycles(1);saved_events=events;
        key_raw=8'hba;cycles(SENSOR-1);key_raw=8'h3a;cycles(ACQUIRE_BOUND+SENSOR+12);
        check(events==saved_events,"digital pulse wholly between polls is not sampled; sensor unit separately checks sub-filter pulses");
        keys(8'hc0);keys(0);quiet;
        repeat(3) begin keys(8'h01);audio_frames(2);keys(0);end
        quiet;
        $display("PASS [C] single/two/four keys, FIFO batch order, steal, old off, retrigger, short pulse and release");

        phase_name="D real default control panel";boot(0);keys(1);audio_frames(8);
        timbre_key=1;panel_check(0,1);timbre_key=0;panel_check(0,1);
        control_start=cycle;control_pcm=-1;control_serial=-1;measure_control=1;bend_up_key=1;
        control_guard=0;
        while(dut.touch_keys[11]!==1'b1 && control_guard<=ACQUIRE_BOUND) begin cycles(1);control_guard=control_guard+1;end
        check(control_guard<=ACQUIRE_BOUND,"control input acquisition bound includes polling");
        control_commit=cycle;
        cycles(CTRL_WAIT-1);check(dut.bend===0,"default bend must not update early");
        cycles(1);control_apply=cycle;check(dut.bend===4'sd2,"default bend updates at CTRL+3 exactly");
        control_guard=0;
        while(control_serial<0 && control_guard<4*FRAME+300) begin cycles(1);control_guard=control_guard+1;end
        check(control_pcm>=0 && control_serial>=0,"changed bend reaches phase-derived PCM and externally verified I2S frame");
        $display("LATENCY control raw_config=%0d config_pcm=%0d pcm_i2s_msb=%0d total=%0d clocks (%0.6f ms)",
                 control_apply-control_start,control_pcm-control_apply,control_serial-control_pcm,
                 control_serial-control_start,(control_serial-control_start)/27000.0);
        $display("LATENCY serial_control A_input_commit=%0d D_commit_i2s=%0d C_input_i2s=%0d margin=%0d clocks",
                 control_commit-control_start,control_serial-control_commit,control_serial-control_start,BUDGET-(control_serial-control_start));
        measure_control=0;
        if(control_serial-control_start>BUDGET) begin
            failures=failures+1;
            $display("FAIL [F-control] default control-to-I2S=%0d clocks exceeds %0d clocks (10ms)",
                     control_serial-control_start,BUDGET);
        end else
            $display("PASS [F-control] default control-to-I2S=%0d clocks <=%0d; margin=%0d clocks",
                     control_serial-control_start,BUDGET,BUDGET-(control_serial-control_start));
        bend_up_key=0;panel_check(1,0);
        bend_down_key=1;panel_check(1,-2);
        bend_up_key=1;panel_check(1,0);
        bend_down_key=0;panel_check(1,2);
        bend_up_key=0;panel_check(1,0);
        volume_up_key=1;panel_check(2,20480);volume_up_key=0;panel_check(2,20480);
        volume_down_key=1;panel_check(2,16384);volume_down_key=0;panel_check(2,16384);
        check(dut.timbre===1,"long timbre press toggles only once");
        $display("PASS [D] default %0d-cycle debounce; timbre, +/-2/0, gain and real audio propagation",CONTROL);
        phase_name="A running reset/restart";boot(0);audio_frames(8);
        check(dut.mixed_sample===0 && dut.voice_gate===0,"running reset clears sound and old events");
        check(total_decoded>1000,"substantial real stereo stream checked across resets");
        $display("PASS [E] external Philips I2S decoded=%0d stereo frames; exact produced PCM, 16-bit MSB-first, LR polarity, reset resync",total_decoded);
        $display("PASS [F-key] default sensor raw-to-I2S <=10ms; max frame-to-PCM=%0d clocks",max_pipeline);
        check(CONTROL_BOUND<=BUDGET,"conservative worst frame alignment stays within 10ms");
        $display("LATENCY_BOUND control=%0d clocks (%0.6f ms), margin=%0d clocks; digital bound, not board measurement",
                 CONTROL_BOUND,CONTROL_BOUND/27000.0,BUDGET-CONTROL_BOUND);
        $display("RESULT assertions=%0d functional=PASS performance_failures=%0d",assertions,failures);
        if(failures) $finish_and_return(1);
        $display("PASS: tb_top_integration all checks passed");$finish;
    end
    initial begin #1200000000; $display("FAIL: integration timeout (1200ms simulated)");$finish_and_return(1);end
endmodule
`default_nettype wire
`end_keywords
