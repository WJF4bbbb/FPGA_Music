// Owner: C
// STATUS: INTERFACE STUB ONLY. Replace tie-offs with synthesizable logic.
// See docs/interfaces.md before changing ports.
`default_nettype none
module note_event (
    input wire clk,
    input wire rst_n,
    input wire [7:0] key_state,
    input wire evt_ready,
    output wire evt_valid,
    output wire [2:0] evt_key_id,
    output wire [6:0] evt_note,
    output wire evt_on,
    output wire [31:0] overflow_count
);
    // TODO: multi-key changes -> event FIFO (>=32 entries).
    // Notes by key: 60,62,64,65,67,69,71,72. Hold valid until handshake.
    assign evt_valid = 1'b0;
    assign evt_key_id = 3'd0;
    assign evt_note = 7'd60;
    assign evt_on = 1'b0;
    assign overflow_count = 32'd0;
endmodule
`default_nettype wire
