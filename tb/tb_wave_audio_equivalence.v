`timescale 1ns/1ps
`default_nettype none
// Historical top and historical telemetry are frozen under tb/fixtures.
// Probe every output clock edge, including I2S bits, while real input filters,
// voice synthesis, controls and waveform capture/transmission are active.
module tb_wave_audio_equivalence;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [15:0] keys=0;
    wire scl_new,scl_old,sdo_new,sdo_old;
    wire bclk_new,bclk_old,lrclk_new,lrclk_old,data_new,data_old,pa_new,pa_old;
    wire uart_new,uart_old;
    // The external model's propagation/timeout must be accelerated with SCL.
    ttp229_model #(.DATA_DELAY_NS(1),.TIMEOUT_NS(500)) sensor_new(.rst_n(rst_n),.scl(scl_new),.keys(keys),.sdo(sdo_new));
    ttp229_model #(.DATA_DELAY_NS(1),.TIMEOUT_NS(500)) sensor_old(.rst_n(rst_n),.scl(scl_old),.keys(keys),.sdo(sdo_old));
    top #(.TTP_STARTUP_CYCLES(8),.TTP_SCL_HALF_CYCLES(8),.TTP_FRAME_GAP_CYCLES(80),.TOUCH_CTRL_FILT(8)) dut (
        .clk(clk),.rst_n(rst_n),.ttp_scl(scl_new),.ttp_sdo(sdo_new),.test_enable(1'b0),
        .bclk(bclk_new),.lrclk(lrclk_new),.i2s_data(data_new),.pa_en(pa_new),
        .uart_rx_pin(1'b1),.uart_tx_pin(uart_new)
    );
    top_before_waveform #(.TTP_STARTUP_CYCLES(8),.TTP_SCL_HALF_CYCLES(8),.TTP_FRAME_GAP_CYCLES(80),.TOUCH_CTRL_FILT(8)) reference (
        .clk(clk),.rst_n(rst_n),.ttp_scl(scl_old),.ttp_sdo(sdo_old),.test_enable(1'b0),
        .bclk(bclk_old),.lrclk(lrclk_old),.i2s_data(data_old),.pa_en(pa_old),
        .uart_rx_pin(1'b1),.uart_tx_pin(uart_old)
    );
    // Accelerate telemetry cadence/baud only; audio still runs exactly its
    // production pipeline and 576-clock sample period in both instances.
    defparam dut.u_telemetry.CLK_HZ=2700000;
    defparam reference.u_telemetry.CLK_HZ=2700000;
    integer clocks=0,samples=0,nonzero=0,wave_cycles=0,all_voices=0;
    integer uart_file,uart_bit;
    reg [7:0] uart_byte;
    initial begin
        uart_file=$fopen("sim/waveform_audio_uart.hex","w");
        wait(rst_n);
        forever begin
            @(negedge uart_new);
            repeat(11) @(posedge clk);
            for(uart_bit=0;uart_bit<8;uart_bit=uart_bit+1) begin
                repeat(23) @(posedge clk); uart_byte[uart_bit]=uart_new;
            end
            repeat(23) @(posedge clk);
            if(uart_new!==1) $fatal(1,"audio probe UART stop bit invalid");
            $fdisplay(uart_file,"%02x",uart_byte);
        end
    end
    reg [3:0] seen_timbres=0;
    always @(posedge clk) begin
        #1;
        if(rst_n) begin
            clocks=clocks+1;
            if({scl_new,bclk_new,lrclk_new,data_new,pa_new} !==
               {scl_old,bclk_old,lrclk_old,data_old,pa_old})
                $fatal(1,"external audio/control outputs differ at clock %0d",clocks);
            if({dut.mixed_sample,dut.mixed_valid,dut.voice_note,dut.voice_gate,dut.master_gain,dut.timbre,dut.bend} !==
               {reference.mixed_sample,reference.mixed_valid,reference.voice_note,reference.voice_gate,reference.master_gain,reference.timbre,reference.bend})
                $fatal(1,"audio/voice/control samples differ at clock %0d",clocks);
            if(dut.mixed_valid) begin
                samples=samples+1;
                if(dut.mixed_sample!=0) nonzero=nonzero+1;
                seen_timbres[dut.timbre]=1;
            end
            if(&dut.voice_gate) all_voices=all_voices+1;
            if(dut.u_telemetry.sending && dut.u_telemetry.packet_wave) wave_cycles=wave_cycles+1;
        end
    end
    task cycles(input integer count); repeat(count) @(negedge clk); endtask
    integer t;
    initial begin
        cycles(10);rst_n=1;keys=16'h0001;cycles(60000);
        keys=16'h000f;cycles(100000);
        for(t=0;t<3;t=t+1) begin
            keys=16'h010f;cycles(20000);
            keys=16'h000f;cycles(70000);
        end
        keys=16'h040f;cycles(20000); // Volume down while four notes sound.
        keys=16'h000f;cycles(100000);
        keys=0;cycles(650000);
        if(samples<1000 || nonzero<100 || wave_cycles==0 || all_voices==0 || seen_timbres!=4'b1111)
            $fatal(1,"equivalence coverage insufficient: samples=%0d nonzero=%0d waves=%0d voices=%0d timbres=%b",samples,nonzero,wave_cycles,all_voices,seen_timbres);
        $display("PASS: tb_wave_audio_equivalence %0d clocks, %0d PCM samples, %0d nonzero, four voices/four timbres; zero baseline differences",clocks,samples,nonzero);
        $fclose(uart_file);
        $finish;
    end
    initial begin #20000000;$fatal(1,"audio equivalence timeout");end
endmodule
`default_nettype wire
