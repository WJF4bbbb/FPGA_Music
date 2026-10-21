// Owner: A. Connected scaffold; submodules remain silent stubs.
`default_nettype none
module top #(parameter NVOICE = 4) (
    input wire clk,
    input wire rst_n,
    input wire [7:0] key_raw,
    input wire timbre_key,
    input wire bend_up_key,
    input wire bend_down_key,
    input wire volume_up_key,
    input wire volume_down_key,
    input wire test_enable,
    output wire bclk,
    output wire lrclk,
    output wire i2s_data
);
    // TODO A: async assert / synchronous release reset conditioner.
    // For now rst_n is assumed to be already conditioned by the caller.
    // TODO A: synchronize test_enable and flush/reset voices on mode change.
    wire sample_en, bit_fall_ce, frame_load;
    wire [4:0] bit_index;
    wire [7:0] key_state;
    wire [1:0] timbre;
    wire signed [3:0] bend;
    wire [15:0] master_gain;
    // TODO A: snapshot timbre/bend/master_gain at frame start.
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
    wire [31:0] overflow_count, underrun_count, clip_count;

    clk_gen u_clk_gen (.clk(clk), .rst_n(rst_n), .sample_en(sample_en),
        .bclk(bclk), .lrclk(lrclk), .bit_fall_ce(bit_fall_ce),
        .bit_index(bit_index), .frame_load(frame_load));
    key_scan u_key_scan (.clk(clk), .rst_n(rst_n), .key_raw(key_raw), .key_state(key_state));
    timbre_sel u_timbre_sel (.clk(clk), .rst_n(rst_n), .timbre_key(timbre_key),
        .bend_up_key(bend_up_key), .bend_down_key(bend_down_key),
        .volume_up_key(volume_up_key), .volume_down_key(volume_down_key),
        .timbre(timbre), .bend(bend), .master_gain(master_gain));
    note_event u_note_event (.clk(clk), .rst_n(rst_n), .key_state(key_state),
        .evt_ready(real_ready), .evt_valid(real_valid), .evt_key_id(real_key),
        .evt_note(real_note), .evt_on(real_on), .overflow_count(overflow_count));
    test_mode u_test_mode (.clk(clk), .rst_n(rst_n), .enable(test_enable),
        .evt_ready(test_ready), .evt_valid(test_valid), .evt_key_id(test_key),
        .evt_note(test_note), .evt_on(test_on));
    assign evt_valid = test_enable ? test_valid : real_valid;
    assign evt_key   = test_enable ? test_key   : real_key;
    assign evt_note  = test_enable ? test_note  : real_note;
    assign evt_on    = test_enable ? test_on    : real_on;
    assign real_ready = evt_ready & ~test_enable;
    assign test_ready = evt_ready & test_enable;
    voice_alloc #(.NVOICE(NVOICE)) u_voice_alloc (.clk(clk), .rst_n(rst_n),
        .evt_valid(evt_valid), .evt_ready(evt_ready), .evt_key_id(evt_key),
        .evt_note(evt_note), .evt_on(evt_on), .voice_busy(voice_busy), .env_done(env_done),
        .voice_note(voice_note), .voice_gate(voice_gate), .voice_trigger(voice_trigger));
    genvar i;
    generate for (i=0; i<NVOICE; i=i+1) begin: voices
        wire signed [15:0] wave;
        wire wave_valid;
        osc u_osc (.clk(clk), .rst_n(rst_n), .sample_en(sample_en),
            .note(voice_note[i*7 +: 7]), .bend(bend), .timbre(timbre),
            .wave(wave), .valid(wave_valid));
        adsr u_adsr (.clk(clk), .rst_n(rst_n), .wave_valid(wave_valid), .wave(wave),
            .gate(voice_gate[i]), .trigger(voice_trigger[i]),
            .sample(voice_samples[i*16 +: 16]), .valid(voice_valid[i]),
            .busy(voice_busy[i]), .env_done(env_done[i]));
    end endgenerate
    mixer #(.NVOICE(NVOICE)) u_mixer (.clk(clk), .rst_n(rst_n),
        .voice_samples(voice_samples), .voice_valid(voice_valid), .master_gain(master_gain),
        .sample(mixed_sample), .valid(mixed_valid), .clip_count(clip_count));
    i2s_tx u_i2s_tx (.clk(clk), .rst_n(rst_n), .sample(mixed_sample),
        .sample_valid(mixed_valid), .bit_fall_ce(bit_fall_ce), .bit_index(bit_index),
        .frame_load(frame_load), .data(i2s_data), .underrun_count(underrun_count));
endmodule
`default_nettype wire
