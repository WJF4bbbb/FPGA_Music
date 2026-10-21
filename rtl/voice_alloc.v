// Owner: B
// STATUS: INTERFACE STUB ONLY. Replace tie-offs with synthesizable logic.
// See docs/interfaces.md before changing ports.
`default_nettype none
module voice_alloc #(parameter NVOICE = 4) (
    input wire clk,
    input wire rst_n,
    input wire evt_valid,
    output wire evt_ready,
    input wire [2:0] evt_key_id,
    input wire [6:0] evt_note,
    input wire evt_on,
    input wire [NVOICE-1:0] voice_busy,
    input wire [NVOICE-1:0] env_done,
    output wire [NVOICE*7-1:0] voice_note,
    output wire [NVOICE-1:0] voice_gate,
    output wire [NVOICE-1:0] voice_trigger
);
    // TODO: key identity, release occupancy, retrigger, deterministic stealing.
    assign evt_ready = 1'b1;
    assign voice_note = {NVOICE{7'd60}};
    assign voice_gate = {NVOICE{1'b0}};
    assign voice_trigger = {NVOICE{1'b0}};
endmodule
`default_nettype wire
