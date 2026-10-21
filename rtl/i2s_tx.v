// Owner: A
// STATUS: INTERFACE STUB ONLY. Replace tie-offs with synthesizable logic.
// See docs/interfaces.md before changing ports.
`default_nettype none
module i2s_tx (
    input wire clk,
    input wire rst_n,
    input wire signed [15:0] sample,
    input wire sample_valid,
    input wire bit_fall_ce,
    input wire [4:0] bit_index,
    input wire frame_load,
    output wire data,
    output wire [31:0] underrun_count
);
    // TODO: pending/frame buffers; Philips I2S one-bit WS lead.
    // Stereo slots are 16 bits each; duplicate the mono frame sample.
    assign data = 1'b0;
    assign underrun_count = 32'd0;
endmodule
`default_nettype wire
