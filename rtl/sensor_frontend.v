// Owner: C
// V1.1 (docs/interfaces.md §4.1): 8-channel independent sync + debounce.
// Active-high key_raw (top convention). key_state = 1 => triggered.
// Photoelectric initial filter = 5400 cycles (0.2ms @ 27MHz).
// Mechanical substitutes need their own debounce budget - not 0.2ms by default.
`default_nettype none
`timescale 1ns/1ps
module sensor_frontend (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  key_raw,
    output reg  [7:0]  key_state
);
    parameter FILT_CYCLES = 5400;          // stable cycles required before a change is accepted
    localparam CNT_W = 13;                 // holds (FILT_CYCLES-1); raise if FILT_CYCLES > 8192

    reg [7:0] sync1, sync2;                // two-stage synchronizer per channel (shared)
    reg [CNT_W-1:0] filt_cnt [0:7];        // per-channel debounce counters
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1 <= 8'd0;
            sync2 <= 8'd0;
            key_state <= 8'd0;
            for (i = 0; i < 8; i = i + 1)
                filt_cnt[i] <= {CNT_W{1'b0}};
        end else begin
            sync1 <= key_raw;
            sync2 <= sync1;
            for (i = 0; i < 8; i = i + 1) begin
                if (sync2[i] != key_state[i]) begin
                    if (filt_cnt[i] == (FILT_CYCLES - 1)) begin
                        key_state[i] <= sync2[i];          // accept the change
                        filt_cnt[i]  <= {CNT_W{1'b0}};
                    end else
                        filt_cnt[i] <= filt_cnt[i] + 1'b1; // still unstable
                end else
                    filt_cnt[i] <= {CNT_W{1'b0}};           // stable, no pending change
            end
        end
    end
endmodule
`default_nettype wire
