`timescale 1ns/1ps
`default_nettype none
// Fixed 27 MHz -> 1.5 MHz BCLK / 46875 Hz stereo frame timing.
// rst_n is asynchronously asserted and synchronously released by top.
module audio_timing (
    input  wire       clk,
    input  wire       rst_n,
    output reg        bclk,
    output reg        lrclk,
    output wire       bclk_rise_ce,
    output wire       bclk_fall_ce,
    output reg  [4:0] bit_index,
    output wire       frame_load,
    output wire       frame_tick
);
    localparam [3:0] HALF_COUNT_LAST = 4'd8;
    localparam [4:0] LEFT_LSB_INDEX = 5'd15;
    localparam [4:0] RIGHT_LSB_INDEX = 5'd31;
    reg [3:0] half_cnt;

    // Decode pre-edge state so downstream clk registers act on the SAME edge
    // as the external BCLK transition. These enables must never be clocks.
    assign bclk_rise_ce = rst_n && (half_cnt == HALF_COUNT_LAST) && !bclk;
    assign bclk_fall_ce = rst_n && (half_cnt == HALF_COUNT_LAST) &&  bclk;
    assign frame_load = bclk_fall_ce && (bit_index == RIGHT_LSB_INDEX);
    assign frame_tick = frame_load;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            half_cnt <= 4'd0;
            bclk <= 1'b0;
            lrclk <= 1'b1;
            bit_index <= RIGHT_LSB_INDEX;
        end else begin
            if (half_cnt == HALF_COUNT_LAST) begin
                half_cnt <= 4'd0;
                bclk <= ~bclk;
            end else begin
                half_cnt <= half_cnt + 4'd1;
            end

            if (bclk_fall_ce) begin
                // Consumers see the OLD index; advance for the next fall.
                bit_index <= bit_index + 5'd1;
                // Philips I2S: change WS while sending the old channel LSB,
                // one full BCLK before preparing the next channel MSB.
                if (bit_index == LEFT_LSB_INDEX)
                    lrclk <= 1'b1;
                else if (bit_index == RIGHT_LSB_INDEX)
                    lrclk <= 1'b0;
                // At index 31 TX sends OLD frame LSB and loads NEW frame.
            end
        end
    end
endmodule
`default_nettype wire
