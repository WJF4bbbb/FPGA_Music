// Owner: A
// STATUS: INTERFACE STUB ONLY. Replace tie-offs with synthesizable logic.
// See docs/interfaces.md before changing ports.
`default_nettype none
module test_mode (
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire evt_ready,
    output wire evt_valid,
    output wire [2:0] evt_key_id,
    output wire [6:0] evt_note,
    output wire evt_on
);
    // TODO: emit note events through the normal voice engine; no PCM playback.
    // Hold valid/data while ready=0. Stop/reset voices on mode transitions.
    assign evt_valid = 1'b0;
    assign evt_key_id = 3'd0;
    assign evt_note = 7'd60;
    assign evt_on = 1'b0;
endmodule
`default_nettype wire
