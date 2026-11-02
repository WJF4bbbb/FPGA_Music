`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// bt_cmd_parse.v —— 蓝牙命令解析（字节流 -> 音符事件）
//
// 【负责人】feature/bt-in 分支
// 【当前状态】空壳：不产生任何事件，owner 恒 0（蓝牙不接管）。
//
// 【端口约定】
//   data / valid  : 来自 uart_rx 的字节流
//   evt_valid     : 有一个音符事件要送给 voice_alloc
//   evt_ready     : voice_alloc 说"我收下了"（握手）
//                   **evt_valid 和 evt_ready 同时为高的那个时钟才算送达**
//   evt_key_id    : 0~7，虚拟键号（和触摸板 TP0~TP7 用同一套编号）
//   evt_note      : MIDI 音符号，60=C4
//   evt_on        : 1=按下，0=松开
//   owner         : 1=蓝牙接管输入，触摸板让位；0=交还触摸板
//
// 【帧格式】见 docs/BT_LINK_SPLIT.md，5 字节：
//   AA 55 | 02 | note | on/off | CRC8
//
// 【实现要点】
//   1. 先做字节级状态机：找 AA -> 找 55 -> 收类型 -> 收数据 -> 校验
//   2. 校验不过就丢弃并回到找 AA，不要死等
//   3. 收到第一条合法音符命令时把 owner 拉高
//   4. 收到"释放控制"命令（type=03）时把 owner 拉低
//   5. evt_valid 必须等 evt_ready 才撤销，否则 voice_alloc 会漏事件
//
// 【自检要求】必须配 tb_bt_cmd_parse.v，覆盖：
//   正常按下/松开、CRC 错误、帧头错位、连续快速按键。
// ============================================================================
module bt_cmd_parse (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       valid,
    output reg        evt_valid,
    input  wire       evt_ready,
    output reg  [2:0] evt_key_id,
    output reg  [6:0] evt_note,
    output reg        evt_on,
    output reg        owner
);
    // ---- 空壳实现：永不产生事件，永不接管 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            evt_valid  <= 1'b0;
            evt_key_id <= 3'd0;
            evt_note   <= 7'd0;
            evt_on     <= 1'b0;
            owner      <= 1'b0;
        end else begin
            evt_valid <= 1'b0;
        end
    end
endmodule
`default_nettype wire
