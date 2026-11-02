`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// bt_cmd_parse.v —— 蓝牙命令解析（字节流 -> 音符事件）
//
// 【负责人】feature/bt-in 分支
// 【状态】已实现
//
// 【端口约定】（冻结，未改动）
//   data / valid  : 来自 uart_rx 的字节流
//   evt_valid     : 有一个音符事件要送给 voice_alloc
//   evt_ready     : voice_alloc 说"我收下了"（握手）
//                   **evt_valid 和 evt_ready 同时为高的那个时钟才算送达**
//   evt_key_id    : 0~7，虚拟键号（和触摸板 TP0~TP7 用同一套编号）
//   evt_note      : MIDI 音符号，60=C4
//   evt_on        : 1=按下，0=松开
//   owner         : 1=蓝牙接管输入，触摸板让位；0=交还触摸板
//
// 【帧格式】AA 55 | 类型 | 长度 | 数据... | CRC8
//   CRC8 覆盖"类型字节到数据末尾"（不含帧头和 CRC 自身），多项式 0x07，初值 0。
//   type=02 长度=2 : data[0]=MIDI 音号，data[1]=flags
//                    flags.bit0 = 1 按下 / 0 松开，flags.bit3:1 = 键号 0~7
//   type=03 长度=0 : 交还触摸板控制权
//
// 【关键时序】
//   evt_valid 置位后**必须保持到 evt_ready 为高的那一拍**才撤销。
//   如果只在置位后一拍就撤销，voice_alloc 会漏事件（表现为偶发少一个音）。
//   这里用"握手才清零"的写法，而不是每拍默认清零。
//
// 【owner 与事件的同拍关系】
//   收到第一条合法音符帧时 owner 和 evt_valid 在同一拍置位，下一拍两者同时可见，
//   top 里 bt_evt_ready = ... && bt_owner && evt_ready 才成立，
//   所以事件不会因为"owner 还是 0"而丢失。
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
    localparam [7:0] H0     = 8'hAA;
    localparam [7:0] H1     = 8'h55;
    localparam [7:0] T_NOTE = 8'h02;
    localparam [7:0] T_REL  = 8'h03;

    localparam [2:0] S_H0   = 3'd0,
                     S_H1   = 3'd1,
                     S_TYPE = 3'd2,
                     S_LEN  = 3'd3,
                     S_PL   = 3'd4,
                     S_CRC  = 3'd5;

    reg [2:0]  state;
    reg [7:0]  ftype;
    reg [7:0]  flen;
    reg [7:0]  pl [0:7];
    reg [3:0]  pidx;
    reg [7:0]  crc;

    // CRC8（多项式 0x07，不反转，不异或输出），单步：吃一个字节
    function [7:0] crc8_step;
        input [7:0] d;
        input [7:0] c;
        integer i;
        begin
            crc8_step = c ^ d;
            for (i = 0; i < 8; i = i + 1)
                crc8_step = crc8_step[7] ? ((crc8_step << 1) ^ 8'h07)
                                         :  (crc8_step << 1);
        end
    endfunction

    wire crc_ok = (data == crc);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_H0;
            ftype      <= 8'd0;
            flen       <= 8'd0;
            pidx       <= 4'd0;
            crc        <= 8'd0;
            evt_valid  <= 1'b0;
            evt_key_id <= 3'd0;
            evt_note   <= 7'd0;
            evt_on     <= 1'b0;
            owner      <= 1'b0;
        end else begin
            // ---- 握手撤销：只有 evt_ready 为高才撤，保证 voice_alloc 收到 ----
            if (evt_valid && evt_ready)
                evt_valid <= 1'b0;

            if (valid) begin
                case (state)
                    S_H0: begin
                        if (data == H0) state <= S_H1;
                    end

                    S_H1: begin
                        if (data == H1)      state <= S_TYPE;
                        else if (data != H0) state <= S_H0;  // 连发 AA 时停在 S_H1
                    end

                    S_TYPE: begin
                        ftype <= data;
                        crc   <= crc8_step(8'h00, data);
                        state <= S_LEN;
                    end

                    S_LEN: begin
                        flen <= data;
                        crc  <= crc8_step(crc, data);
                        pidx <= 4'd0;
                        if (data > 8'd8) begin
                            state <= S_H0;                 // 长度非法，丢弃重来
                        end else if (data == 8'd0) begin
                            state <= S_CRC;
                        end else begin
                            state <= S_PL;
                        end
                    end

                    S_PL: begin
                        pl[pidx] <= data;
                        crc      <= crc8_step(crc, data);
                        if (pidx == flen[3:0] - 4'd1)
                            state <= S_CRC;
                        else
                            pidx <= pidx + 4'd1;
                    end

                    S_CRC: begin
                        if (crc_ok) begin
                            if (ftype == T_NOTE && flen >= 8'd2) begin
                                // flags.bit3:1 = 键号，flags.bit0 = 按下/松开
                                evt_key_id <= pl[1][3:1];
                                evt_note   <= pl[0][6:0];
                                evt_on     <= pl[1][0];
                                evt_valid  <= 1'b1;
                                owner      <= 1'b1;        // 蓝牙接管
                            end else if (ftype == T_REL) begin
                                owner      <= 1'b0;        // 交还触摸板
                            end
                            // 其它类型：校验通过但与本模块无关，静默忽略
                        end
                        // CRC 失败：若这个字节本身是 AA，可能已经是下一帧的头
                        state <= crc_ok ? S_H0 : ((data == H0) ? S_H1 : S_H0);
                    end

                    default: state <= S_H0;
                endcase
            end
        end
    end
endmodule
`default_nettype wire
