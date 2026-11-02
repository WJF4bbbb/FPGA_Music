`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// telemetry.v —— 遥测打包 + 串口发送
//
// 【负责人】feature/bt-out 分支
// 【当前状态】空壳：tx 恒高，不发送任何数据。
//
// 【这个模块干什么】
//   每 33 ms（约 30 Hz）把整机当前状态抓成一份快照，打成 20 字节的帧，
//   通过 uart_tx 发给 HC-05，再由网页显示出来。
//
// 【端口约定（输入全部只读，不会影响发声逻辑）】
//   clk / rst_n   : 系统时钟与复位
//   touch_keys    : 16 键位图，bit N = TPN 被按下（来自 ttp229_reader）
//   voice_note    : 4 个声部的 MIDI 音符号，每声部 7 位，第 0 声部在最低位
//   voice_gate    : 4 个声部的按键状态，bit N = 第 N 声部 gate 为高
//   timbre        : 当前音色 0~3
//   bend          : 弯音，有符号 -2~+2（半音）
//   master_gain   : 主音量 Q16，65535 = 1.0
//   clip_count    : 削顶累计次数，只增不减
//   tx            : 串口输出，接 HC-05 的 RXD
//   tx_busy       : 发送忙，仅供调试观察
//
// 【实现要点】
//   1. **必须先做快照再发**：在 30 Hz 脉冲上把 20 个字节一次性打进寄存器，
//      然后从寄存器组发送。否则边发边读实时信号，一帧里会出现
//      "前几个字节是旧值、后几个字节是新值"，网页上音名和状态对不上。
//   2. 帧间隔要留够：20 字节 × 10 比特 / 115200 ≈ 1.7 ms，
//      30 Hz 的周期是 33 ms，余量充足。
//   3. CRC8 多项式用 0x07（CRC-8/ATM），初值 0x00。
//   4. telemetry 内部自己例化 uart_tx，top 只连引脚。
//
// 【自检要求】必须配 tb_telemetry.v：
//   喂一组固定输入，抓 tx 波形解出 20 字节，逐字段比对。
// ============================================================================
module telemetry #(
    parameter integer CLK_HZ = 27000000,
    parameter integer BAUD   = 115200,
    parameter integer NVOICE = 4
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire [15:0]         touch_keys,
    input  wire [NVOICE*7-1:0] voice_note,
    input  wire [NVOICE-1:0]   voice_gate,
    input  wire [1:0]          timbre,
    input  wire signed [3:0]   bend,
    input  wire [15:0]         master_gain,
    input  wire [31:0]         clip_count,
    output wire                tx,
    output wire                tx_busy
);
    // ---- 空壳实现：串口线保持空闲高电平，不发任何数据 ----
    // 填充时删掉这两行 assign，改为例化 uart_tx 并把快照数据喂给它。
    assign tx      = 1'b1;
    assign tx_busy = 1'b0;
endmodule
`default_nettype wire
