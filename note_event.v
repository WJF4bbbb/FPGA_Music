// Owner: C
// V1.1 (docs/interfaces.md §4.3): key_state -> queued note events.
// >=32 entry FIFO, releases-before-presses ordering (then ascending key_id),
// ready/valid backpressure (whole event held until handshake), and explicit
// saturation counting (no silent note_off drops).
`default_nettype none
`timescale 1ns/1ps
module note_event (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  key_state,
    input  wire        evt_ready,
    output wire        evt_valid,
    output wire [2:0]  evt_key_id,
    output wire [6:0]  evt_note,
    output wire        evt_on,
    output reg  [31:0] overflow_count
);

    localparam DEPTH = 32;
    localparam AW    = 5;            // 2^AW = DEPTH

    reg [AW-1:0] head, tail;
    reg [5:0]    cnt;                // 0..DEPTH
    reg [7:0]    prev_key_state;
    reg [2:0]    fifo_key  [0:DEPTH-1];
    reg [6:0]    fifo_note [0:DEPTH-1];
    reg          fifo_on   [0:DEPTH-1];

    // locals (module-level so this stays portable to Verilog-2001)
    integer      i;
    reg [AW-1:0] h, t;
    reg [5:0]    c;
    reg [7:0]    pv;
    reg [7:0]    change;
    reg [5:0]    dropped;

    // Output the current head entry combinationally, so a just-pushed entry is
    // visible on the same cycle evt_valid rises (no one-cycle stale read).
    assign evt_valid  = (cnt != 6'd0);
    assign evt_key_id = fifo_key[head];
    assign evt_note   = fifo_note[head];
    assign evt_on     = fifo_on[head];

    function [6:0] midi_of;
        input [2:0] k;
        begin
            case (k)
                3'd0: midi_of = 7'd60;
                3'd1: midi_of = 7'd62;
                3'd2: midi_of = 7'd64;
                3'd3: midi_of = 7'd65;
                3'd4: midi_of = 7'd67;
                3'd5: midi_of = 7'd69;
                3'd6: midi_of = 7'd71;
                3'd7: midi_of = 7'd72;
                default: midi_of = 7'd60;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= {AW{1'b0}};
            tail <= {AW{1'b0}};
            cnt  <= 6'd0;
            prev_key_state <= 8'd0;
            overflow_count <= 32'd0;
        end else begin
            h = head; t = tail; c = cnt; pv = prev_key_state; dropped = 6'd0;

            // ---- POP (consumer handshake) ----
            if ((c != 6'd0) && evt_ready) begin
                h = h + 1'b1;
                c = c - 1'b1;
            end

            // ---- DETECT & PUSH ----
            change = key_state ^ pv;
            if (change != 8'd0) begin
                // pass 1: releases (on=0), ascending key_id
                // Only a successfully-pushed bit advances pv; a dropped bit keeps
                // its old pv so it is retried next cycle (no silent loss, no
                // permanent key-state desync when the FIFO saturates).
                for (i = 0; i < 8; i = i + 1) begin
                    if (change[i] && !key_state[i]) begin
                        if (c < DEPTH) begin
                            fifo_key[t]  <= i[2:0];
                            fifo_note[t] <= midi_of(i[2:0]);
                            fifo_on[t]   <= 1'b0;
                            t = t + 1'b1; c = c + 1'b1;
                            pv[i] = 1'b0;
                        end else
                            dropped = dropped + 1'b1;
                    end
                end
                // pass 2: presses (on=1), ascending key_id
                for (i = 0; i < 8; i = i + 1) begin
                    if (change[i] && key_state[i]) begin
                        if (c < DEPTH) begin
                            fifo_key[t]  <= i[2:0];
                            fifo_note[t] <= midi_of(i[2:0]);
                            fifo_on[t]   <= 1'b1;
                            t = t + 1'b1; c = c + 1'b1;
                            pv[i] = 1'b1;
                        end else
                            dropped = dropped + 1'b1;
                    end
                end
            end

            if (dropped != 6'd0)
                overflow_count <= overflow_count + {26'd0, dropped};

            head <= h; tail <= t; cnt <= c; prev_key_state <= pv;
        end
    end
endmodule
`default_nettype wire
