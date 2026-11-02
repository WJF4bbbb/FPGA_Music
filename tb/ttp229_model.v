`timescale 1ns/1ps
`default_nettype none
// Independent pin-level BSF model, manufacturer V1.1 pp7-8.
// No DUT internals. D0 is TP0; default SCL/SDO active-low.
// keys describes an already detected digital touch, not capacitive scan delay.
module ttp229_model #(
    parameter ACTIVE_LOW=1,
    parameter integer DATA_DELAY_NS=200,
    parameter integer TIMEOUT_NS=2000000
) (
    input wire rst_n,
    input wire scl,
    input wire [15:0] keys,
    output reg sdo
);
    integer bit_number=0, frame_count=0;
    reg [15:0] snapshot=0;
    time last_clock=0, snapshot_time=0;
    wire active_clock = ACTIVE_LOW ? ~scl : scl;
    initial sdo=ACTIVE_LOW ? 1'b1 : 1'b0;
    always @(active_clock or negedge rst_n) begin
        if (!rst_n) begin
            sdo <= ACTIVE_LOW ? 1'b1 : 1'b0;
            bit_number=0;last_clock=0;snapshot=0;frame_count=0;
        end else begin
            if(active_clock===1'b1) begin
                if (last_clock==0 || $time-last_clock>=TIMEOUT_NS) begin
                    bit_number=0;
                    snapshot=keys;
                    snapshot_time=$time;
                    frame_count=frame_count+1;
                end
                if (bit_number<16) begin
                    sdo <= #(DATA_DELAY_NS) (ACTIVE_LOW ? ~snapshot[bit_number] : snapshot[bit_number]);
                    bit_number=bit_number+1;
                end else sdo <= #(DATA_DELAY_NS) (ACTIVE_LOW ? 1'b1 : 1'b0);
            end
            // Timeout is measured from ANY clock transition, not just active edges.
            last_clock=$time;
        end
    end
endmodule
`default_nettype wire
