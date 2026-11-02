`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// uart_rx.v —— 串口接收（8N1，无流控）
//
// 【负责人】feature/bt-in 分支
// 【当前状态】空壳：输出恒 0、valid 恒 0，只为让 top 能编译综合。
//            填充时**保持端口完全不变**，内部随便写。
//
// 【端口约定】
//   clk    : 27 MHz 系统时钟（与全设计同域，没有跨时钟）
//   rst_n  : 低有效复位（接 core_rst_n）
//   rx     : 串口输入线，来自 HC-05 的 TXD，空闲时为高
//   data   : 收到的一个字节（8 位）
//   valid  : 单周期脉冲，data 有效的那个时钟拉高一次
//
// 【实现要点（填充时参考）】
//   1. 先两级同步 rx，消除亚稳态（外部信号和 27 MHz 不同步）
//   2. 检测起始位下降沿 -> 等待半个比特 -> 再每隔一个比特采一次
//   3. 27 MHz / 115200 = 234.375，取 234 分频，误差 +0.16%，可接受
//   4. 采样点取比特中心，不要取边沿
//   5. 停止位如果不是高电平，丢弃这一字节（帧错误）
//
// 【自检要求】必须配 tb_uart_rx.v，用 234 分频的发送模型喂数据，
//            打印 PASS/FAIL，两种语言模式（-g2005 / -g2012）都要过。
// ============================================================================
module uart_rx #(
    parameter integer CLK_HZ = 27000000,
    parameter integer BAUD   = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);
    // ---- 空壳实现：永远收不到数据 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data  <= 8'd0;
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;
        end
    end
endmodule
`default_nettype wire
