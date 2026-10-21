`timescale 1ns/1ps
`default_nettype none
// 27MHz clk域中的16位双声道I2S发送器；时序由audio_timing提供。
module i2s_tx (
    input  wire               clk,
    input  wire               rst_n,
    input  wire signed [15:0] sample,
    input  wire               sample_valid,
    input  wire               bclk_fall_ce,
    input  wire [4:0]         bit_index,
    input  wire               frame_load,
    output reg                data,
    output reg [31:0]         underrun_count
);
    reg signed [15:0] pending_sample;
    reg               pending_valid;
    reg signed [15:0] frame_sample;
    reg               load_started;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_sample <= 16'sd0;
            pending_valid <= 1'b0;
            frame_sample <= 16'sd0;
            load_started <= 1'b0;
            data <= 1'b0;
            underrun_count <= 32'd0;
        end else begin
            // 左右声道复制同一个完整帧样本，均按MSB first发送。
            // 索引31必须读取旧frame_sample的LSB，不能读取新装载样本。
            if (bclk_fall_ce)
                data <= frame_sample[4'd15 - bit_index[3:0]];

            if (frame_load) begin
                load_started <= 1'b1;
                if (pending_valid)
                    frame_sample <= pending_sample;
                else if (load_started && underrun_count != 32'hffffffff)
                    underrun_count <= underrun_count + 32'd1;
                // 无新结果则保留旧帧；首次装载允许零且不计欠载。
                pending_valid <= 1'b0;
            end

            // 该赋值优先于消费清标志：同沿新结果留给下次装载。
            // frame_load读取的仍是沿前的pending_sample/valid，禁止旁路。
            // 若一帧内提交多次，以最后一次结果作为待发送样本。
            if (sample_valid) begin
                pending_sample <= sample;
                pending_valid <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
