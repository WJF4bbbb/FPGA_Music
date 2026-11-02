`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// telemetry.v —— 遥测打包 + 串口发送
//
// 【负责人】feature/bt-out 分支
//
// 【这个模块干什么】
//   每 33 ms（约 30 Hz）把整机当前状态抓成一份快照，打成 20 字节的帧，
//   通过内部的 uart_tx 发给 HC-05，再由网页显示出来。
//
// 【端口约定（输入全部只读，不会影响发声逻辑）】
//   touch_keys    : 16 键位图，bit N = TPN 被按下
//   voice_note    : 4 个声部的 MIDI 音符号，每声部 7 位，第 0 声部在最低位
//   voice_gate    : 4 个声部的按键状态，bit N = 第 N 声部 gate 为高
//   timbre        : 当前音色 0~3
//   bend          : 弯音，有符号 -2~+2（半音）
//   master_gain   : 主音量 Q16，65535 = 1.0
//   clip_count    : 削顶累计次数，只增不减
//   tx            : 串口输出，接 HC-05 的 RXD
//   tx_busy       : 发送忙，仅供调试观察
//
// 【帧格式】20 字节，见 docs/BT_LINK_SPLIT.md §6.2
//   0     AA          帧头
//   1     55          帧头
//   2     01          类型 = 状态帧
//   3     0F          长度 = 15
//   4..5  keys        小端
//   6..9  notes[0..3] 每字节一个声部
//   10    gates       低 4 位
//   11    timbre
//   12    bend        补码
//   13..14 gain       小端
//   15..18 clip       小端
//   19    CRC8        覆盖偏移 2..18
//
// 【为什么要先快照再发】
//   发完 20 字节要 20*10*234 = 46800 个时钟 ≈ 1.73 ms。
//   如果边发边读实时信号，一帧里前几个字节是旧值、后几个字节是新值，
//   网页上音名和状态会对不上。所以先把 15 个数据锁进 s_* 寄存器，
//   发送期间冻结，保证一帧内自洽。
//
// 【参数约束】当前只支持 NVOICE=4（帧格式按 4 声部固定）。
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
    // 30 Hz 快照节拍
    localparam integer SNAP_DIV = CLK_HZ / 30;

    // ---- CRC8：多项式 0x07，初值 0x00 ----
    function [7:0] crc8_step;
        input [7:0] d;
        input [7:0] c;
        integer i;
        reg [7:0] x;
        begin
            x = c ^ d;
            for (i = 0; i < 8; i = i + 1)
                x = x[7] ? ((x << 1) ^ 8'h07) : (x << 1);
            crc8_step = x;
        end
    endfunction

    // 一次算完整帧的 CRC（覆盖 类型 + 长度 + 15 字节数据）
    function [7:0] calc_crc;
        input [15:0] k;
        input [27:0] n;
        input [3:0]  g;
        input [1:0]  t;
        input [3:0]  b;
        input [15:0] gn;
        input [31:0] cp;
        reg [7:0] x;
        begin
            x = 8'h00;
            x = crc8_step(8'h01, x);            // 类型
            x = crc8_step(8'h0F, x);            // 长度
            x = crc8_step(k[7:0],    x);
            x = crc8_step(k[15:8],   x);
            x = crc8_step(n[6:0],    x);
            x = crc8_step(n[13:7],   x);
            x = crc8_step(n[20:14],  x);
            x = crc8_step(n[27:21],  x);
            x = crc8_step({4'd0, g}, x);
            x = crc8_step({6'd0, t}, x);
            x = crc8_step({{4{b[3]}}, b}, x);   // 符号扩展成 8 位
            x = crc8_step(gn[7:0],   x);
            x = crc8_step(gn[15:8],  x);
            x = crc8_step(cp[7:0],   x);
            x = crc8_step(cp[15:8],  x);
            x = crc8_step(cp[23:16], x);
            x = crc8_step(cp[31:24], x);
            calc_crc = x;
        end
    endfunction

    // ---- 快照寄存器 ----
    reg [31:0] tick;
    reg [15:0] s_keys;
    reg [27:0] s_notes;
    reg [3:0]  s_gates;
    reg [1:0]  s_timbre;
    reg [3:0]  s_bend;
    reg [15:0] s_gain;
    reg [31:0] s_clip;
    reg [7:0]  s_crc;

    // ---- 发送状态 ----
    reg [4:0] byte_idx;
    reg       sending;
    reg [7:0] tx_data;
    reg       tx_send;
    wire      tx_busy_int;

    wire snap_pulse = (tick == SNAP_DIV - 1);

    // 快照：发送期间冻结，保证一帧内数据自洽
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick     <= 32'd0;
            s_keys   <= 16'd0;
            s_notes  <= 28'd0;
            s_gates  <= 4'd0;
            s_timbre <= 2'd0;
            s_bend   <= 4'd0;
            s_gain   <= 16'd0;
            s_clip   <= 32'd0;
            s_crc    <= 8'd0;
        end else begin
            tick <= snap_pulse ? 32'd0 : (tick + 32'd1);
            if (snap_pulse && !sending) begin
                s_keys   <= touch_keys;
                s_notes  <= voice_note;
                s_gates  <= voice_gate;
                s_timbre <= timbre;
                s_bend   <= bend;
                s_gain   <= master_gain;
                s_clip   <= clip_count;
                s_crc    <= calc_crc(touch_keys, voice_note, voice_gate,
                                     timbre, bend, master_gain, clip_count);
            end
        end
    end

    // ---- 按索引取第 idx 个字节 ----
    function [7:0] frame_byte;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  frame_byte = 8'hAA;
                5'd1:  frame_byte = 8'h55;
                5'd2:  frame_byte = 8'h01;
                5'd3:  frame_byte = 8'h0F;
                5'd4:  frame_byte = s_keys[7:0];
                5'd5:  frame_byte = s_keys[15:8];
                5'd6:  frame_byte = s_notes[6:0];
                5'd7:  frame_byte = s_notes[13:7];
                5'd8:  frame_byte = s_notes[20:14];
                5'd9:  frame_byte = s_notes[27:21];
                5'd10: frame_byte = {4'd0, s_gates};
                5'd11: frame_byte = {6'd0, s_timbre};
                5'd12: frame_byte = {{4{s_bend[3]}}, s_bend};
                5'd13: frame_byte = s_gain[7:0];
                5'd14: frame_byte = s_gain[15:8];
                5'd15: frame_byte = s_clip[7:0];
                5'd16: frame_byte = s_clip[15:8];
                5'd17: frame_byte = s_clip[23:16];
                5'd18: frame_byte = s_clip[31:24];
                5'd19: frame_byte = s_crc;
                default: frame_byte = 8'h00;
            endcase
        end
    endfunction

    // ---- 逐字节发送 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_idx <= 5'd0;
            sending  <= 1'b0;
            tx_data  <= 8'd0;
            tx_send  <= 1'b0;
        end else begin
            tx_send <= 1'b0;    // 默认只给一个周期的脉冲
            if (snap_pulse && !sending) begin
                sending  <= 1'b1;
                byte_idx <= 5'd0;
            end else if (sending && !tx_busy_int && !tx_send) begin
                tx_data  <= frame_byte(byte_idx);
                tx_send  <= 1'b1;
                if (byte_idx == 5'd19)
                    sending <= 1'b0;
                else
                    byte_idx <= byte_idx + 5'd1;
            end
        end
    end

    // ---- 串口发送器 ----
    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst_n(rst_n),
        .data(tx_data), .send(tx_send),
        .tx(tx), .busy(tx_busy_int)
    );

    assign tx_busy = tx_busy_int;

endmodule
`default_nettype wire
