`timescale 1ns/1ps
`default_nettype none
// Real-rate protocol/filter/audio. Only the 0.5 s startup is shortened; the
// reader unit test separately exercises the complete default startup twice.
module tb_ttp229_latency;
    parameter integer CTRL_FILTER=135000;
    parameter integer FIRST_CONTROL=0,PHASE_COUNT=6;
    reg clk=0,rst_n=0,test_enable=0;
    reg [15:0] touch=0;
    wire ttp_scl,ttp_sdo,bclk,lrclk,i2s_data,pa_en;
    wire uart_tx_pin;          // 蓝牙遥测输出，本测试台不关心
    reg  uart_rx_pin = 1'b1;   // 蓝牙接收，拉高=串口空闲（模块未接）
    top #(.TTP_STARTUP_CYCLES(270),.TOUCH_CTRL_FILT(CTRL_FILTER)) dut(.*);
    ttp229_model chip(.rst_n(rst_n),.scl(ttp_scl),.keys(touch),.sdo(ttp_sdo));
    always #18.518518518 clk=~clk;
    localparam integer BUDGET=270000,ACQUIRE_BOUND=89378;
    // Current remainder + 3ms idle + next read; sync/filter; all frame phases.
    localparam integer CONTROL_BOUND=ACQUIRE_BOUND+135003+3*576+128+36;
    integer cycle=0,epoch=0,applied_epoch=0,phase_ticks=0,compute_tag=0;
    integer source_cycle=0,commit_cycle=-1,config_cycle=-1,pcm_cycle=-1,serial_cycle=-1,wire_cycle=-1;
    integer first_event=-1,qread=0,qwrite=0,frames=0,cases=0,guard=0;
    integer max_a=0,max_b=0,max_c=0,max_d=0,max_wire_c=0,kind=0,phase=0,offset=0;
    reg measure=0,pending=0,loaded=0;
    reg [15:0] pending_pcm=0,expect_word[0:65535];
    integer pending_tag=0,expect_tag[0:65535],production_cycle=0,expect_cycle[0:65535];
    integer expected_value=0,pre_timbre=0,phase_offset_log=0;
    integer oracle_epoch=0,mix_index,oracle_index,reference_gain=0,reference_mix=0,reference_sum;
    integer golden_wave[0:3],golden_sample[0:3],target_delta[0:3],actual_delta,oracle_error;
    reg [31:0] old_phase[0:3];
    reg signed [63:0] reference_product;
    real frequency,ratio;
    reg signed [3:0] oracle_bend;
    wire signed [15:0] wave_bus[0:3];
    assign wave_bus[0]=dut.voices[0].wave;
    assign wave_bus[1]=dut.voices[1].wave;
    assign wave_bus[2]=dut.voices[2].wave;
    assign wave_bus[3]=dut.voices[3].wave;
    function automatic [31:0] phase_of(input integer n);
        case(n) 0:phase_of=dut.voices[0].u_osc.phase;1:phase_of=dut.voices[1].u_osc.phase;
                2:phase_of=dut.voices[2].u_osc.phase;default:phase_of=dut.voices[3].u_osc.phase;endcase
    endfunction
    function automatic integer level_of(input integer n);
        case(n) 0:level_of=dut.voices[0].u_adsr.level;1:level_of=dut.voices[1].u_adsr.level;
                2:level_of=dut.voices[2].u_adsr.level;default:level_of=dut.voices[3].u_adsr.level;endcase
    endfunction
    // 独立波形模型：必须与 rtl/osc.v 的 wave_of() 逐位一致。
    // timbre 取 0~3：0 正弦 / 1 方波 / 2 锯齿 / 3 三角。
    function automatic integer wave_of_model(input [1:0] t, input [31:0] ph);
        reg [15:0] raw;
        begin
            case (t)
                2'd0: wave_of_model = $rtoi(32767.0*$sin(6.283185307179586*ph[31:24]/256.0)
                                            + (ph[31] ? -0.5 : 0.5));
                2'd1: wave_of_model = ph[31] ? -32768 : 32767;
                2'd2: begin raw = {~ph[31], ph[30:16]};                  // 锯齿
                            wave_of_model = $signed(raw); end
                2'd3: begin raw = ph[31] ? ~ph[30:15] : ph[30:15];       // 三角
                            wave_of_model = $signed({~raw[15], raw[14:0]}); end
                default: wave_of_model = 0;
            endcase
        end
    endfunction
    task check(input bit ok,input string message);
        if(ok!==1'b1) begin $display("FAIL latency cycle=%0d: %s",cycle,message);$finish_and_return(1);end
    endtask
    task cycles(input integer n);repeat(n) @(negedge clk);#1;endtask
    task first_clock;
        begin
            @(negedge ttp_scl);#201;
            while(chip.bit_number!=1) begin @(negedge ttp_scl);#201;end
        end
    endtask
    always @(posedge clk) begin
        cycle=cycle+1;
        if(!dut.core_rst_n) begin
            qread=0;qwrite=0;pending=0;loaded=0;phase_ticks=0;compute_tag=0;
        end else begin
            if(measure && first_event<0 && dut.evt_valid && dut.evt_ready) first_event=cycle;
            if(dut.frame_tick) begin
                reference_gain=dut.master_gain;
                check(qwrite<65536,"I2S scoreboard capacity");
                check(!loaded || pending,"new PCM before every load");
                expect_word[qwrite]=pending ? pending_pcm : 0;
                expect_tag[qwrite]=pending ? pending_tag : 0;
                expect_cycle[qwrite]=production_cycle;
                qwrite=qwrite+1;pending=0;loaded=1;
                if(applied_epoch==epoch && applied_epoch>0) begin
                    phase_ticks=phase_ticks+1;
                    // Two ticks include the changed DDS phase even for bend.
                    compute_tag=phase_ticks>=2 ? applied_epoch : 0;
                end else begin phase_ticks=0;compute_tag=0;end
            end
            // Prove sample provenance with the mathematical NEW-config wave,
            // envelope multiplication and frame-snapshotted gain. Never label
            // an arbitrary observed nonzero PCM as a changed-control sample.
            if(&dut.voice_valid) begin
                reference_sum=0;
                for(mix_index=0;mix_index<4;mix_index=mix_index+1) begin
                    reference_product=golden_wave[mix_index]*level_of(mix_index);
                    golden_sample[mix_index]=reference_product>>>15;
                    check($signed(dut.voice_samples[mix_index*16+:16])==golden_sample[mix_index],"phase/wave oracle propagates through actual ADSR multiplication");
                    reference_sum=reference_sum+golden_sample[mix_index];
                end
                reference_product=(reference_sum>>>2)*$signed({1'b0,16'(reference_gain)});
                reference_mix=reference_product>>>16;
                if(reference_mix>32767) reference_mix=32767;
                if(reference_mix< -32768) reference_mix=-32768;
            end
            if(dut.mixed_valid) begin
                check($signed(dut.mixed_sample)==reference_mix,"mixed PCM independently matches new waveform/envelope/gain");
                check(oracle_epoch==compute_tag,"epoch tag requires verified DDS/waveform provenance");
                pending_pcm=pa_en ? dut.mixed_sample : 16'd0;
                pending_tag=compute_tag;pending=1;production_cycle=cycle;
                if(measure && pcm_cycle<0 && pending_tag==epoch && pending_pcm!=0) pcm_cycle=cycle;
            end
        end
    end
    // Independent audio math for EVERY swept phase, not only the ordinary
    // integration case. Failed or stale bend/timbre propagation is fatal.
    always @(posedge clk) if(dut.core_rst_n && dut.frame_tick) begin
        oracle_bend=dut.bend;
        for(oracle_index=0;oracle_index<4;oracle_index=oracle_index+1) begin
            old_phase[oracle_index]=phase_of(oracle_index);
            frequency=440.0*(2.0**(($itor(dut.voice_note[oracle_index*7+:7])-69.0)/12.0));
            case(dut.bend) 2:ratio=73562.0/65536.0;-2:ratio=58385.0/65536.0;default:ratio=1.0;endcase
            target_delta[oracle_index]=$rtoi(frequency*4294967296.0/46875.0*ratio);
            golden_wave[oracle_index]=wave_of_model(dut.timbre,old_phase[oracle_index]);
        end
        #1;
        for(oracle_index=0;oracle_index<4;oracle_index=oracle_index+1) begin
            actual_delta=phase_of(oracle_index)-old_phase[oracle_index];
            // Icarus treats $abs(scalar-array[index]) as unsigned when negative.
            // Scalar signed subtraction preserves the intended magnitude.
            oracle_error=actual_delta-target_delta[oracle_index];
            if(oracle_error<0) oracle_error=-oracle_error;
            check(actual_delta>0 && oracle_error<target_delta[oracle_index]/10000,
                  $sformatf("DDS advance independently matches current bent frequency: lane=%0d actual=%0d expected=%0d note=%0d bend_pre=%0d bend_now=%0d phase_old=%h phase_new=%h",
                            oracle_index,actual_delta,target_delta[oracle_index],dut.voice_note[oracle_index*7+:7],oracle_bend,dut.bend,
                            old_phase[oracle_index],phase_of(oracle_index)));
            oracle_error=$signed(wave_bus[oracle_index])-golden_wave[oracle_index];
            if(oracle_error<0) oracle_error=-oracle_error;
            check(oracle_error<=1,"wave independently matches current timbre and phase");
        end
        oracle_epoch=compute_tag;
    end
    // Timestamp actual SDO frame-data availability as well as the EARLIER
    // model digital-change time. The latter includes a missed poll snapshot.
    always @(negedge ttp_scl) begin
        #201;
        if(measure && wire_cycle<0 && chip.snapshot===touch && chip.bit_number==1) wire_cycle=cycle;
    end
    reg previous_ws=1,start_next=0,rx_active=0,channel=0,have_left=0;
    reg [15:0] word_bits=0,left_word=0;
    integer bits=0,left_start=0;
    always @(posedge bclk or negedge rst_n) begin
        if(!rst_n) begin previous_ws=1;start_next=0;rx_active=0;have_left=0;bits=0;end
        else begin
            if(start_next) begin
                channel=previous_ws;word_bits=0;bits=0;rx_active=1;start_next=0;
                if(!channel) left_start=cycle;
            end
            if(rx_active) begin
                word_bits={word_bits[14:0],i2s_data};bits=bits+1;
                if(bits==16) begin
                    rx_active=0;
                    check(qread<qwrite && word_bits===expect_word[qread],"external decoded I2S equals complete corresponding PCM");
                    if(!channel) begin
                        left_word=word_bits;have_left=1;
                        if(measure && serial_cycle<0 && expect_tag[qread]==epoch && word_bits!=0) begin
                            check(expect_cycle[qread]>=pcm_cycle,"decoded frame has changed-control PCM provenance");
                            serial_cycle=left_start;
                        end
                    end else begin
                        check(have_left && left_word===word_bits,"both I2S channels complete and identical");
                        have_left=0;qread=qread+1;frames=frames+1;
                    end
                end
            end
            if(lrclk!=previous_ws) begin
                check(!rx_active,"Philips one-bit WS lead");start_next=1;previous_ws=lrclk;
            end
        end
    end
    task await_bitmap(input [15:0] value);
        begin
            guard=0;
            while((!dut.touch_valid || dut.touch_keys!==value) && guard<=ACQUIRE_BOUND) begin cycles(1);guard=guard+1;end
            check(guard<=ACQUIRE_BOUND,"reader acquisition respects worst-poll bound");
        end
    endtask
    task begin_measure(input [15:0] value,input integer phase_offset);
        begin
            first_clock;cycles(phase_offset);
            epoch=epoch+1;applied_epoch=0;phase_ticks=0;compute_tag=0;
            source_cycle=cycle;commit_cycle=-1;config_cycle=-1;pcm_cycle=-1;serial_cycle=-1;wire_cycle=-1;first_event=-1;
            measure=1;touch=value;
            await_bitmap(value);commit_cycle=cycle;
        end
    endtask
    task finish_measure(input string label_text);
        integer a,b,c,d;
        begin
            applied_epoch=epoch;phase_ticks=0;guard=0;
            while(serial_cycle<0 && cycle-source_cycle<=BUDGET+576) begin cycles(1);guard=guard+1;end
            check(serial_cycle>=0 && pcm_cycle>=0 && wire_cycle>=0,"all digital, commit, PCM and decoded-I2S endpoints observed");
            a=commit_cycle-source_cycle;b=serial_cycle-commit_cycle;c=serial_cycle-source_cycle;d=serial_cycle-commit_cycle;
            check(c<=BUDGET,$sformatf("%s complete input-to-I2S=%0d must be <=270000",label_text,c));
            check(a<=ACQUIRE_BOUND,"A includes whole worst polling/serialization wait");
            if(a>max_a) max_a=a;if(b>max_b) max_b=b;if(c>max_c) max_c=c;if(d>max_d) max_d=d;
            if(serial_cycle-wire_cycle>max_wire_c) max_wire_c=serial_cycle-wire_cycle;
            $display("LATENCY_CASE %s phase=%0d A_available_commit=%0d A_wire_commit=%0d B_or_D_commit_i2s=%0d C_available_i2s=%0d C_wire_i2s=%0d config=%0d pcm=%0d event=%0d margin=%0d clocks",
                     label_text,phase_offset_log,a,commit_cycle-wire_cycle,b,c,serial_cycle-wire_cycle,
                     config_cycle-source_cycle,pcm_cycle-source_cycle,first_event<0 ? -1 : first_event-source_cycle,BUDGET-c);
            cases=cases+1;measure=0;applied_epoch=0;
        end
    endtask
    initial begin
        cycles(4);rst_n=1;await_bitmap(0);cycles(2*576);
        // Four simultaneous notes, with update just AFTER the current snapshot.
        begin_measure(16'h000f,0);phase_offset_log=0;
        guard=0;while(dut.voice_gate!==4'b1111 && guard<BUDGET) begin cycles(1);guard=guard+1;end
        check(dut.voice_gate===4'b1111,"four simultaneous notes reach four real voice gates");
        config_cycle=cycle;finish_measure("four_notes");
        cycles(32*576);
        for(phase=0;phase<PHASE_COUNT;phase=phase+1) begin
            case(phase) 0:offset=0;1:offset=134;2:offset=269;3:offset=575;4:offset=4184;default:offset=81000;endcase
            for(kind=FIRST_CONTROL;kind<5;kind=kind+1) begin
                case(kind)
                    0:begin expected_value=(dut.timbre+1)&3;begin_measure(16'h010f,offset);end
                    1:begin expected_value=dut.master_gain+4096;begin_measure(16'h020f,offset);end
                    2:begin expected_value=dut.master_gain-4096;begin_measure(16'h040f,offset);end
                    3:begin expected_value=2;begin_measure(16'h080f,offset);end
                    4:begin expected_value=-2;begin_measure(16'h100f,offset);end
                endcase
                phase_offset_log=offset;guard=0;
                while(((kind==0 && dut.timbre!=expected_value) ||
                       ((kind==1 || kind==2) && dut.master_gain!=expected_value) ||
                       (kind>=3 && $signed(dut.bend)!=expected_value)) && cycle-source_cycle<=BUDGET+576) cycles(1);
                config_cycle=cycle;
                check(cycle-source_cycle<=BUDGET,"control stable filter updates before digital budget");
                finish_measure($sformatf("control_%0d",kind));
                check(dut.voice_gate===4'b1111,"control touch does not release held notes");
                touch=16'h000f;await_bitmap(16'h000f);cycles(135003+2*576);
                check(dut.bend===0,"bend releases through serial/filter boundary");
            end
        end
        // Notes and control arrive in the SAME module snapshot.
        touch=0;await_bitmap(0);cycles(135003+2*576);
        expected_value=dut.master_gain+4096;
        begin_measure(16'h020f,0);phase_offset_log=0;
        while((dut.master_gain!=expected_value || dut.voice_gate!==4'b1111) && cycle-source_cycle<=BUDGET+576) cycles(1);
        config_cycle=cycle;finish_measure("mixed_four_notes_volume");
        check(CONTROL_BOUND<=BUDGET,"conservative proof covers ALL poll and audio-frame alignments");
        $display("LATENCY_MAX A=%0d B_or_D=%0d C=%0d C_wire=%0d margin=%0d clocks; cases=%0d decoded_frames=%0d",max_a,max_b,max_c,max_wire_c,BUDGET-max_c,cases,frames);
        $display("LATENCY_BOUND input_i2s=%0d clocks (%0.6f ms) margin=%0d clocks; excludes sensor scan, includes worst poll",CONTROL_BOUND,CONTROL_BOUND/27000.0,BUDGET-CONTROL_BOUND);
        $display("PASS: tb_ttp229_latency all checks passed");$finish;
    end
    initial begin #1500000000;$display("FAIL latency: timeout");$finish_and_return(1);end
endmodule
`default_nettype wire
