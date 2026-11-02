`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// uart_tx.v —— 串口发送（8N1，无流控）
//
// 【负责人】feature/bt-out 分支
//
// 【端口约定】
//   clk    : 27 MHz 系统时钟
//   rst_n  : 低有效复位
//   data   : 要发的字节
//   send   : 单周期脉冲，拉高的那个时钟锁存 data 并开始发送
//   tx     : 串口输出线，接 HC-05 的 RXD。空闲为高，起始位为低
//   busy   : 1=正在发送，0=空闲。send 只能在 busy=0 时给
//
// 【实现思路】
//   把一帧看成 10 个比特：起始位(0) + 8 个数据位(低位先出) + 停止位(1)。
//   用一个 10 位移位寄存器 shifter 一次性装好，然后每 DIV 个时钟挪一位。
//
//     shifter = { 1'b1, data[7:0], 1'b0 }
//                ↑停止   ↑数据      ↑起始
//     bit_idx:    9      8..1        0
//
//   DIV = CLK_HZ / BAUD = 27000000 / 115200 = 234（向下取整）
//   实际波特率 27000000/234 = 115384.6，误差 +0.16%，远小于 UART 容忍的 2%。
//
// 【为什么不用状态机写 10 个状态】
//   移位寄存器 + 一个计数器就够，代码短、综合出来的资源也少。
//   起始位在 send 那一拍就立即拉低，不额外等一个周期，这样时序最紧。
// ============================================================================
module uart_tx #(
    parameter integer CLK_HZ = 27000000,
    parameter integer BAUD   = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       send,
    output reg        tx,
    output reg        busy
);
    // 一个比特持续多少个系统时钟
    localparam integer DIV = CLK_HZ / BAUD;

    reg [15:0] cnt;       // 比特内计数 0 .. DIV-1
    reg [3:0]  bit_idx;   // 当前发到第几位 0..9
    reg [9:0]  shifter;   // {stop, data, start}
    reg        running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx      <= 1'b1;
            busy    <= 1'b0;
            running <= 1'b0;
            cnt     <= 16'd0;
            bit_idx <= 4'd0;
            shifter <= 10'h3FF;
        end else if (!running) begin
            // 空闲：tx 保持高电平
            tx   <= 1'b1;
            busy <= 1'b0;
            cnt  <= 16'd0;
            if (send) begin
                // 一次性装好整帧，起始位当拍就拉低
                shifter <= {1'b1, data, 1'b0};
                bit_idx <= 4'd0;
                tx      <= 1'b0;
                busy    <= 1'b1;
                running <= 1'b1;
            end
        end else begin
            if (cnt == DIV[15:0] - 16'd1) begin
                cnt <= 16'd0;
                if (bit_idx == 4'd9) begin
                    // 停止位发完，回空闲
                    running <= 1'b0;
                    busy    <= 1'b0;
                    tx      <= 1'b1;
                end else begin
                    bit_idx <= bit_idx + 4'd1;
                    tx      <= shifter[bit_idx + 4'd1];
                end
            end else begin
                cnt <= cnt + 16'd1;
            end
        end
    end
endmodule
`default_nettype wire
