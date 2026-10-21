// Owner: A
// STATUS: INTERFACE STUB ONLY. Replace tie-offs with synthesizable logic.
// See docs/interfaces.md before changing ports.
`default_nettype none
module clk_gen (
    input wire clk,
    input wire rst_n,
    output wire sample_en,
    output wire bclk,
    output wire lrclk,
    output wire bit_fall_ce,
    output wire [4:0] bit_index,
    output wire frame_load
);
    // TODO: 27MHz, BCLK half-period=9 clocks, 576 clocks/frame.
    // sample_en requests NEXT frame; frame_load latches the completed frame.
    assign sample_en = 1'b0;
    assign bclk = 1'b0;
    assign lrclk = 1'b0;
    assign bit_fall_ce = 1'b0;
    assign bit_index = 5'd0;
    assign frame_load = 1'b0;
endmodule
`default_nettype wire
