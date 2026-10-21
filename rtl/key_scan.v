// Owner: C
// STATUS: INTERFACE STUB ONLY. Replace tie-offs with synthesizable logic.
// See docs/interfaces.md before changing ports.
`default_nettype none
module key_scan (
    input wire clk,
    input wire rst_n,
    input wire [7:0] key_raw,
    output wire [7:0] key_state
);
    // TODO: per-input two-flop synchronizer and independent stable filter.
    // Optical input starting budget: 5400 clocks = 0.2ms at 27MHz.
    assign key_state = 8'd0;
endmodule
`default_nettype wire
