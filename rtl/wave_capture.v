`timescale 1ns/1ps
`default_nettype none
// Passive audio probe. No ready/backpressure signal enters the audio pipeline.
// The single RAM is frozen from ready until release_capture; a busy request is
// intentionally dropped rather than corrupting a capture being transmitted.
module wave_capture #(
    parameter integer SAMPLE_COUNT=512,
    parameter integer ADDR_WIDTH=9,
    parameter integer TRIGGER_WAIT=256
) (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire release_capture,
    input wire signed [15:0] sample,
    input wire sample_valid,
    input wire [ADDR_WIDTH-1:0] read_addr,
    output reg signed [15:0] read_data,
    output reg ready,
    output wire busy,
    output reg triggered
);
    localparam [1:0] IDLE=2'd0, WAIT_TRIGGER=2'd1, CAPTURING=2'd2;
    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] write_addr;
    reg [31:0] wait_count;
    reg previous_negative;
    (* syn_ramstyle = "block_ram" *) reg [15:0] samples [0:SAMPLE_COUNT-1];
    assign busy = (state != IDLE);
    wire first_sample = state == WAIT_TRIGGER &&
        ((previous_negative && !sample[15]) || wait_count == TRIGGER_WAIT-1);
    wire write_enable = rst_n && sample_valid && (first_sample || state == CAPTURING);
    wire [ADDR_WIDTH-1:0] memory_write_addr = first_sample ? {ADDR_WIDTH{1'b0}} : write_addr;

    // Unreset memory and a clocked read allow an actual embedded RAM mapping.
    // Data is meaningful only while ready. Reset invalidates the publication.
    // A single syntactic write port is essential to Gowin's block-RAM inference.
    always @(posedge clk)
        if (write_enable) samples[memory_write_addr] <= sample;
    always @(posedge clk)
        read_data <= samples[read_addr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            ready <= 1'b0;
            triggered <= 1'b0;
            write_addr <= {ADDR_WIDTH{1'b0}};
            wait_count <= 32'd0;
            previous_negative <= 1'b0;
        end else begin
            if (sample_valid) previous_negative <= sample[15];
            case (state)
                IDLE: begin
                    if (release_capture) ready <= 1'b0;
                    if (start && !ready) begin
                        state <= WAIT_TRIGGER;
                        wait_count <= 32'd0;
                        triggered <= 1'b0;
                    end
                end
                WAIT_TRIGGER: if (sample_valid) begin
                    if ((previous_negative && !sample[15]) || wait_count == TRIGGER_WAIT-1) begin
                        triggered <= previous_negative && !sample[15];
                        write_addr <= {{(ADDR_WIDTH-1){1'b0}},1'b1};
                        if (SAMPLE_COUNT == 1) begin
                            ready <= 1'b1;
                            state <= IDLE;
                        end else state <= CAPTURING;
                    end else wait_count <= wait_count + 32'd1;
                end
                CAPTURING: if (sample_valid) begin
                    if (write_addr == SAMPLE_COUNT-1) begin
                        ready <= 1'b1;
                        state <= IDLE;
                    end else write_addr <= write_addr + 1'b1;
                end
                default: begin state <= IDLE; ready <= 1'b0; end
            endcase
        end
    end
endmodule
`default_nettype wire
