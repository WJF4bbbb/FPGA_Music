// Owner: B
// STATUS: INTERFACE STUB ONLY. Replace tie-offs with synthesizable logic.
// See docs/interfaces.md before changing ports.
`default_nettype none
module mixer #(parameter NVOICE = 4) (
    input wire clk,
    input wire rst_n,
    input wire [NVOICE*16-1:0] voice_samples,
    input wire [NVOICE-1:0] voice_valid,
    input wire [15:0] master_gain,
    output wire signed [15:0] sample,
    output wire valid,
    output wire [31:0] clip_count
);
    // TODO: signed per-lane extraction, wide sum, fixed headroom, saturation.
    // All lane valid flags refer to the same requested frame.
    assign sample = 16'sd0;
    assign valid = 1'b0;
    assign clip_count = 32'd0;
endmodule
`default_nettype wire
