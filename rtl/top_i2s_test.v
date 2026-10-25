
`timescale 1ns/1ps
`default_nettype none

module top_i2s_test (
    input  wire clk,
    input  wire rst_n,
    output wire i2s_bclk,
    output wire i2s_lrclk,
    output wire i2s_data
);

    wire bclk_rise_ce;
    wire bclk_fall_ce;
    wire [4:0] bit_index;
    wire frame_load;
    wire frame_tick;

    wire [31:0] underrun_count;

    // 27 MHz -> I2S timing
    audio_timing u_audio_timing (
        .clk(clk),
        .rst_n(rst_n),
        .bclk(i2s_bclk),
        .lrclk(i2s_lrclk),
        .bclk_rise_ce(bclk_rise_ce),
        .bclk_fall_ce(bclk_fall_ce),
        .bit_index(bit_index),
        .frame_load(frame_load),
        .frame_tick(frame_tick)
    );

    // Fixed PCM test pattern.
    // Update sample on each frame boundary.
    // The transmitter captures this sample
    // for use on a subsequent frame.
    reg signed [15:0] test_sample;
    reg sample_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            test_sample  <= 16'sh2000;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= frame_tick;
            if (frame_tick)
                test_sample <= -test_sample;
        end
    end

    // Philips I2S transmitter
    i2s_tx u_i2s_tx (
        .clk(clk),
        .rst_n(rst_n),
        .sample(test_sample),
        .sample_valid(sample_valid),
        .bclk_fall_ce(bclk_fall_ce),
        .bit_index(bit_index),
        .frame_load(frame_load),
        .data(i2s_data),
        .underrun_count(underrun_count)
    );

endmodule

`default_nettype wire
