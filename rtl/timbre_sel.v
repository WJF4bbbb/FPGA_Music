// Owner: C
// STATUS: INTERFACE STUB ONLY. Replace tie-offs with synthesizable logic.
// See docs/interfaces.md before changing ports.
`default_nettype none
module timbre_sel (
    input wire clk,
    input wire rst_n,
    input wire timbre_key,
    input wire bend_up_key,
    input wire bend_down_key,
    input wire volume_up_key,
    input wire volume_down_key,
    output wire [1:0] timbre,
    output wire signed [3:0] bend,
    output wire [15:0] master_gain
);
    // TODO: synchronize/debounce panel keys; one change per press.
    // bend is in semitones (-2/0/+2 initially). Gain 0..65535.
    assign timbre = 2'd0;
    assign bend = 4'sd0;
    assign master_gain = 16'hFFFF;
endmodule
`default_nettype wire
