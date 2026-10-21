// Owner: B
// STATUS: INTERFACE STUB ONLY. Replace tie-offs with synthesizable logic.
// See docs/interfaces.md before changing ports.
`default_nettype none
module adsr #(parameter FS_HZ = 46875) (
    input wire clk,
    input wire rst_n,
    input wire wave_valid,
    input wire signed [15:0] wave,
    input wire gate,
    input wire trigger,
    output wire signed [15:0] sample,
    output wire valid,
    output wire busy,
    output wire env_done
);
    // TODO: latch trigger even between samples; update envelope on wave_valid.
    // Release to zero before clearing busy. Align gate/trigger with frame data.
    assign sample = 16'sd0;
    assign valid = 1'b0;
    assign busy = 1'b0;
    assign env_done = 1'b0;
endmodule
`default_nettype wire
