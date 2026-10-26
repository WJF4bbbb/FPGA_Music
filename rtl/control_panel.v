// Owner: C
// V1.1 (docs/interfaces.md §4.2): control panel.
// 5 keys sync + debounce; timbre toggles once per press; bend is real-time and
// signed; master_gain steps by 4096 with clamp (no wrap).
`default_nettype none
`timescale 1ns/1ps
module control_panel (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        timbre_key,
    input  wire        bend_up_key,
    input  wire        bend_down_key,
    input  wire        volume_up_key,
    input  wire        volume_down_key,
    output reg  [1:0]  timbre,
    output reg  signed [3:0] bend,
    output reg  [15:0] master_gain
);
    parameter CTRL_FILT = 270000;          // ~10ms @27MHz; re-evaluate for mechanical keys
    localparam CW = 19;                    // holds (CTRL_FILT-1); raise if CTRL_FILT > 524288
    localparam VOL_STEP = 16'd4096;
    localparam GAIN_RST = 16'd16384;       // ~25%
    localparam GAIN_MAX = 16'd65535;

    reg [4:0] s1, s2;                       // synchronizers for the 5 keys
    reg [4:0] db;                           // debounced levels
    reg [CW-1:0] cnt [0:4];                 // per-key debounce counters
    integer k;
    // previous debounced levels, for rising-edge detection
    reg db_timbre_prev, db_vup_prev, db_vdn_prev;

    // key mapping into db[]: [4]=timbre [3]=bend_up [2]=bend_down [1]=vol_up [0]=vol_down
    wire [4:0] raw_keys = { timbre_key, bend_up_key, bend_down_key, volume_up_key, volume_down_key };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1 <= 5'd0; s2 <= 5'd0; db <= 5'd0;
            for (k = 0; k < 5; k = k + 1) cnt[k] <= {CW{1'b0}};
            db_timbre_prev <= 1'b0; db_vup_prev <= 1'b0; db_vdn_prev <= 1'b0;
            timbre <= 2'd0;
            bend <= 4'sb0000;
            master_gain <= GAIN_RST;
        end else begin
            s1 <= raw_keys;
            s2 <= s1;
            for (k = 0; k < 5; k = k + 1) begin
                if (s2[k] != db[k]) begin
                    if (cnt[k] == (CTRL_FILT - 1)) begin
                        db[k] <= s2[k];
                        cnt[k] <= {CW{1'b0}};
                    end else
                        cnt[k] <= cnt[k] + 1'b1;
                end else
                    cnt[k] <= {CW{1'b0}};
            end

            // timbre: toggle once per press (rising edge); long press does not repeat
            if (db[4] && !db_timbre_prev)
                timbre <= (timbre == 2'd0) ? 2'd1 : 2'd0;

            // volume: increment/decrement once per press (rising edge), clamp, no wrap
            if (db[1] && !db_vup_prev)
                master_gain <= (master_gain > (GAIN_MAX - VOL_STEP)) ? GAIN_MAX : (master_gain + VOL_STEP);
            else if (db[0] && !db_vdn_prev)
                master_gain <= (master_gain < VOL_STEP) ? 16'd0 : (master_gain - VOL_STEP);

            // bend: real-time, level-based, signed
            if (db[3] && !db[2])      bend <= 4'sb0010;   // only up   => +2
            else if (db[2] && !db[3]) bend <= 4'sb1110;   // only down => -2
            else                      bend <= 4'sb0000;   // neither / both => 0

            db_timbre_prev <= db[4];
            db_vup_prev <= db[1];
            db_vdn_prev <= db[0];
        end
    end
endmodule
`default_nettype wire
