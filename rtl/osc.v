// Owner: B
// STATUS: INTERFACE STUB ONLY. Replace tie-offs with synthesizable logic.
// See docs/interfaces.md before changing ports.
`default_nettype none
module osc #(parameter FS_HZ = 46875) (
    input wire clk,
    input wire rst_n,
    input wire sample_en,
    input wire [6:0] note,
    input wire signed [3:0] bend,
    input wire [1:0] timbre,
    output wire signed [15:0] wave,
    output wire valid
);
    // TODO: independent 32-bit phase; FCW=round(f * 2^32 / FS_HZ).
    // Bend changes FCW without resetting phase. A4 FCW=40315426 at 46875Hz.
    assign wave = 16'sd0;
    assign valid = 1'b0;
endmodule
`default_nettype wire
