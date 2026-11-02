`timescale 1ns/1ps
`default_nettype none
// Serial electrical boundary is normalized once by ttp229_reader.
module top #(
    parameter NVOICE = 4,
    parameter integer TTP_STARTUP_CYCLES=13500000,
    parameter integer TTP_SCL_HALF_CYCLES=135,
    parameter integer TTP_FRAME_GAP_CYCLES=81000,
    parameter TTP_ACTIVE_LOW=1,
    parameter integer TOUCH_CTRL_FILT=135000 // 5 ms at 27 MHz
) (
    input wire clk,
    input wire rst_n,
    input wire ttp_sdo,
    output wire ttp_scl,
    input wire test_enable,
    output wire bclk,
    output wire lrclk,
    output wire i2s_data,
    output reg pa_en
);
    // 外部复位异步拉低，两级同步释放。test_enable同时经过两级同步。
    // 第3个clk锁定启动模式，第4个clk释放全体子模块复位。
    reg [1:0] reset_sync;
    reg [1:0] mode_sync;
    reg mode_locked;
    reg test_mode_latched;
    reg core_rst_n;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            reset_sync <= 2'b00;
            mode_sync <= 2'b00;
            mode_locked <= 1'b0;
            test_mode_latched <= 1'b0;
            core_rst_n <= 1'b0;
        end else begin
            reset_sync <= {reset_sync[0],1'b1};
            mode_sync <= {mode_sync[0],test_enable};
            if(reset_sync[1] && !mode_locked) begin
                test_mode_latched <= mode_sync[1];
                mode_locked <= 1'b1;
            end
            core_rst_n <= reset_sync[1] && mode_locked;
        end
    end

    wire frame_tick, frame_load, bclk_rise_ce, bclk_fall_ce;
    wire [4:0] bit_index;
    wire [7:0] key_state;
    wire [1:0] timbre;
    wire signed [3:0] bend;
    wire [15:0] master_gain;
    wire real_valid, real_ready, real_on;
    wire [2:0] real_key;
    wire [6:0] real_note;
    wire test_valid, test_ready, test_on;
    wire [2:0] test_key;
    wire [6:0] test_note;
    wire evt_valid, evt_ready, evt_on;
    wire [2:0] evt_key;
    wire [6:0] evt_note;
    wire [NVOICE*7-1:0] voice_note;
    wire [NVOICE-1:0] voice_gate, voice_trigger, voice_busy, env_done;
    wire [NVOICE*16-1:0] voice_samples;
    wire [NVOICE-1:0] voice_valid;
    wire signed [15:0] mixed_sample;
    wire mixed_valid;
    wire [15:0] touch_keys;
    wire touch_valid,touch_commit;
    // Centralized mapping. Bits are TP numbers, not package/panel numbers.
    // TP0..7: notes; TP8:timbre, TP9/10:volume +/-; TP11/12:bend +/-.
    // TP13..15 reserved. All consumer inputs are active-high.
    wire [7:0] normalized_keys = touch_valid ? touch_keys[7:0] : 8'd0;
    wire [4:0] normalized_panel =
        touch_valid ? {touch_keys[8],touch_keys[11],touch_keys[12],touch_keys[9],touch_keys[10]} : 5'd0;
    wire signed [15:0] tx_sample = pa_en ? mixed_sample : 16'sd0;
    reg [1:0] pa_startup_boundaries;
    // 统计保留在内部，便于波形观察；不占额外板卡引脚。
    wire [31:0] overflow_count, underrun_count, clip_count;

    // First load aligns I2S. The next two loads terminate two silent stereo
    // frames, but their right LSBs are not sampled until the following rise.
    // Wait until the subsequent left-MSB falling edge before enabling PA.
    // External reset disables PA immediately, including between clk edges.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pa_en <= 1'b0;
            pa_startup_boundaries <= 2'd0;
        end else if (!core_rst_n) begin
            pa_en <= 1'b0;
            pa_startup_boundaries <= 2'd0;
        end else if (!pa_en && bclk_fall_ce) begin
            if (frame_load && pa_startup_boundaries != 2'd3)
                pa_startup_boundaries <= pa_startup_boundaries + 1'b1;
            else if (pa_startup_boundaries == 2'd3 && bit_index == 5'd0)
                pa_en <= 1'b1;
        end
    end

    // 唯一音频时序源，27MHz直分频；备用clk_gen不例化。
    audio_timing u_audio_timing (
        .clk(clk), .rst_n(core_rst_n), .bclk(bclk), .lrclk(lrclk),
        .bclk_rise_ce(bclk_rise_ce), .bclk_fall_ce(bclk_fall_ce),
        .bit_index(bit_index), .frame_load(frame_load), .frame_tick(frame_tick)
    );
    ttp229_reader #(
        .STARTUP_CYCLES(TTP_STARTUP_CYCLES),.SCL_HALF_CYCLES(TTP_SCL_HALF_CYCLES),
        .FRAME_GAP_CYCLES(TTP_FRAME_GAP_CYCLES),.ACTIVE_LOW(TTP_ACTIVE_LOW)
    ) u_ttp229_reader (
        .clk(clk),.rst_n(core_rst_n),.sdo(ttp_sdo),.scl(ttp_scl),
        .keys_state(touch_keys),.keys_valid(touch_valid),.keys_commit(touch_commit)
    );
    // Existing note stability filter (0.2 ms) is unchanged.
    sensor_frontend u_sensor_frontend (
        .clk(clk), .rst_n(core_rst_n), .key_raw(normalized_keys), .key_state(key_state)
    );
    control_panel #(.CTRL_FILT(TOUCH_CTRL_FILT)) u_control_panel (
        .clk(clk), .rst_n(core_rst_n), .timbre_key(normalized_panel[4]),
        .bend_up_key(normalized_panel[3]), .bend_down_key(normalized_panel[2]),
        .volume_up_key(normalized_panel[1]), .volume_down_key(normalized_panel[0]),
        .timbre(timbre), .bend(bend), .master_gain(master_gain)
    );
    note_event u_note_event (
        .clk(clk), .rst_n(core_rst_n), .key_state(key_state),
        .evt_ready(real_ready), .evt_valid(real_valid),
        .evt_key_id(real_key), .evt_note(real_note), .evt_on(real_on),
        .overflow_count(overflow_count)
    );
    test_mode u_test_mode (
        .clk(clk), .rst_n(core_rst_n), .enable(test_mode_latched),
        .evt_ready(test_ready), .evt_valid(test_valid),
        .evt_key_id(test_key), .evt_note(test_note), .evt_on(test_on)
    );

    // 模式启动后固定，运行中的外部开关变化不影响当前事件。
    // 换模式必须统一复位，以同时清除事件队列、声部分配和包络。
    assign evt_valid = core_rst_n && (test_mode_latched ? test_valid : real_valid);
    assign evt_key = test_mode_latched ? test_key : real_key;
    assign evt_note = test_mode_latched ? test_note : real_note;
    assign evt_on = test_mode_latched ? test_on : real_on;
    assign real_ready = core_rst_n && !test_mode_latched && evt_ready;
    assign test_ready = core_rst_n && test_mode_latched && evt_ready;

    // NVOICE合同只支持4或8；B模块的实现与此参数保持一致。
    voice_alloc #(.NVOICE(NVOICE)) u_voice_alloc (
        .clk(clk), .rst_n(core_rst_n), .evt_valid(evt_valid), .evt_ready(evt_ready),
        .evt_key_id(evt_key), .evt_note(evt_note), .evt_on(evt_on),
        .voice_busy(voice_busy), .env_done(env_done), .voice_note(voice_note),
        .voice_gate(voice_gate), .voice_trigger(voice_trigger)
    );
    genvar i;
    generate for(i=0; i<NVOICE; i=i+1) begin: voices
        wire signed [15:0] wave;
        wire wave_valid;
        wire signed [15:0] voice_sample;
        osc #(.FS_HZ(46875)) u_osc (
            .clk(clk), .rst_n(core_rst_n), .frame_tick(frame_tick),
            .note(voice_note[i*7 +: 7]), .bend(bend), .timbre(timbre),
            .wave(wave), .valid(wave_valid)
        );
        adsr #(.FS_HZ(46875)) u_adsr (
            .clk(clk), .rst_n(core_rst_n), .frame_tick(frame_tick),
            .wave_valid(wave_valid), .wave(wave),
            .gate(voice_gate[i]), .trigger(voice_trigger[i]),
            .sample(voice_sample), .valid(voice_valid[i]),
            .busy(voice_busy[i]), .env_done(env_done[i])
        );
        // 第0声部在最低16位；总线仅作为位容器，不当作大signed数。
        assign voice_samples[i*16 +: 16] = voice_sample;
    end endgenerate
    mixer #(.NVOICE(NVOICE)) u_mixer (
        .clk(clk), .rst_n(core_rst_n), .frame_tick(frame_tick),
        .voice_samples(voice_samples), .voice_valid(voice_valid),
        .master_gain(master_gain), .sample(mixed_sample), .valid(mixed_valid),
        .clip_count(clip_count)
    );
    // V1.1发送器已有pending/frame双缓存，top不重复增加缓冲。
    // 当帧启动下一轮计算时，frame_load仅装载之前已完成的结果。
    i2s_tx u_i2s_tx (
        .clk(clk), .rst_n(core_rst_n), .sample(tx_sample), .sample_valid(mixed_valid),
        .bclk_fall_ce(bclk_fall_ce), .bit_index(bit_index), .frame_load(frame_load),
        .data(i2s_data), .underrun_count(underrun_count)
    );
endmodule
`default_nettype wire
