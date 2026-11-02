`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// uart_tx.v —— 串口发送（8N1，无流控）
//
// 【负责人】feature/bt-out 分支
// 【当前状态】空壳：tx 恒高（串口空闲电平），busy 恒 0。
//
// 【端口约定】
//   clk    : 27 MHz 系统时钟
//   rst_n  : 低有效复位
//   data   : 要发的字节
//   send   : 单周期脉冲，拉高的那个时钟锁存 data 并开始发送
//   tx     : 串口输出线，接到 HC-05 的 RXD。空闲为高，起始位为低
//   busy   : 1=正在发送，0=空闲。**send 只能在 busy=0 时给**
//
// 【实现要点】
//   1. 一个比特 = CLK_HZ/BAUD = 234 个时钟（27 MHz / 115200）
//   2. 帧结构：起始位(0) + 8 个数据位(低位先出) + 停止位(1) = 10 比特
//   3. 用计数器分频，不要在 always 里写 #delay（那是仿真语法，不能综合）
//   4. busy 在 send 之后立刻拉高，发完停止位再拉低
//   5. send 和 busy 同时为高时，新数据被忽略（由调用方负责不越界）
//
// 【自检要求】必须配 tb_uart_tx.v，把 tx 波形解回来验证：
//   发 0x00 / 0xFF / 0x55 / 0xAA 各一次，解出的字节必须和发的相同。
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
    // ---- 空壳实现：永远空闲，永远不发 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx   <= 1'b1;
            busy <= 1'b0;
        end
    end
endmodule
`default_nettype wire
