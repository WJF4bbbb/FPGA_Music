`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// bt_at_init.v —— 让 FPGA 自己当"串口助手"，给 HC-05 发 AT 命令改波特率
//
// 【为什么需要它】
//   HC-05 出厂波特率 9600，而本工程全链路是 115200，两边对不上就一个字节都传不通。
//   改模块的波特率只能靠 AT 命令，而本机没有 USB-TTL，所以由 FPGA 代劳。
//
// 【和队友模块的关系】
//   rtl/uart_tx.v 的负责人是 feature/bt-out，在 feature/bt-in 上它还是个空壳
//   （tx 恒高、busy 恒 0）。为了不跨分支改别人的文件，这里的发送逻辑自带一套
//   位转发器（shift register + 分频计数器），只复用本分支自己的 uart_rx 收回复。
//   这也是个独立工具：不进 top，不影响正常演奏固件。
//
// 【时序】
//   38400 8N1。27 MHz / 38400 = 703.125，取 703，误差 +0.018%，
//   一帧 10 位累计偏差 0.018% × 9.5 ≈ 0.002 比特，采样点稳在中心。
//
// 【流程】
//   上电等 BOOT_MS（让模块先启动）
//     -> 发 "AT\r\n"                 等 OK，最多 RETRY_MAX 次
//     -> 发 "AT+UART?\r\n"           等 OK（查询，失败也不致命）
//     -> 发 "AT+UART=115200,0,0\r\n" 等 OK
//     -> done=1，led[4] 常亮
//   任何一步重试耗尽 -> fail=1，led[5] 快闪
//
// 【为什么不发 AT+RESET】
//   部分固件在 AT+UART 成功的瞬间就切到新波特率，此时再用 38400 发 AT+RESET
//   等于给模块灌噪声。发完配置直接断电重启，效果一样且更干净。
//
// 【端口】
//   at_tx : 接模块 RXD（板子 85 脚）。空闲高
//   at_rx : 接模块 TXD（板子 77 脚）。必须有上拉，模块未接时保持空闲高
//   led   : 6 位状态指示，极性由顶层决定
//   done/fail : 给仿真用，顶层可以不接
// ============================================================================
module bt_at_init #(
    parameter integer CLK_HZ     = 27000000,
    parameter integer BAUD       = 38400,
    parameter integer BOOT_MS    = 200,
    parameter integer TIMEOUT_MS = 300,
    parameter integer GAP_MS     = 100,
    parameter integer RETRY_MAX  = 5
) (
    input  wire       clk,
    input  wire       rst_n,
    output reg        at_tx,
    input  wire       at_rx,
    output reg  [5:0] led,
    output reg        done,
    output reg        fail
);

    // ---- 分频与计时 ----
    localparam integer BIT_DIV  = (CLK_HZ + (BAUD / 2)) / BAUD;  // 703
    localparam integer MS_CYC   = CLK_HZ / 1000;                 // 27000
    localparam integer BOOT_CYC = BOOT_MS    * MS_CYC;
    localparam integer TMO_CYC  = TIMEOUT_MS * MS_CYC;
    localparam integer GAP_CYC  = GAP_MS     * MS_CYC;

    // integer 型 localparam 不能做位选择，转成定宽常量再用
    localparam [10:0] BIT_C = BIT_DIV;
    localparam [31:0] BOOT_C = BOOT_CYC;
    localparam [31:0] TMO_C  = TMO_CYC;
    localparam [31:0] GAP_C  = GAP_CYC;
    localparam [3:0]  RTY_C  = RETRY_MAX;

    // ---- 命令表 ----
    // flat 索引：cmd0 = 0..3，cmd1 = 4..13，cmd2 = 14..33，共 34 字节
    //   0..3   "AT\r\n"
    //   4..13  "AT+UART?\r\n"
    //  14..33  "AT+UART=115200,0,0\r\n"
    function [7:0] rom_byte;
        input [5:0] idx;
        begin
            case (idx)
            6'd0:  rom_byte = 8'h41;  // 'A'
            6'd1:  rom_byte = 8'h54;  // 'T'
            6'd2:  rom_byte = 8'h0D;  // CR
            6'd3:  rom_byte = 8'h0A;  // LF
            6'd4:  rom_byte = 8'h41;  // 'A'
            6'd5:  rom_byte = 8'h54;  // 'T'
            6'd6:  rom_byte = 8'h2B;  // '+'
            6'd7:  rom_byte = 8'h55;  // 'U'
            6'd8:  rom_byte = 8'h41;  // 'A'
            6'd9:  rom_byte = 8'h52;  // 'R'
            6'd10: rom_byte = 8'h54;  // 'T'
            6'd11: rom_byte = 8'h3F;  // '?'
            6'd12: rom_byte = 8'h0D;  // CR
            6'd13: rom_byte = 8'h0A;  // LF
            6'd14: rom_byte = 8'h41;  // 'A'
            6'd15: rom_byte = 8'h54;  // 'T'
            6'd16: rom_byte = 8'h2B;  // '+'
            6'd17: rom_byte = 8'h55;  // 'U'
            6'd18: rom_byte = 8'h41;  // 'A'
            6'd19: rom_byte = 8'h52;  // 'R'
            6'd20: rom_byte = 8'h54;  // 'T'
            6'd21: rom_byte = 8'h3D;  // '='
            6'd22: rom_byte = 8'h31;  // '1'
            6'd23: rom_byte = 8'h31;  // '1'
            6'd24: rom_byte = 8'h35;  // '5'
            6'd25: rom_byte = 8'h32;  // '2'
            6'd26: rom_byte = 8'h30;  // '0'
            6'd27: rom_byte = 8'h30;  // '0'
            6'd28: rom_byte = 8'h2C;  // ','
            6'd29: rom_byte = 8'h30;  // '0'
            6'd30: rom_byte = 8'h2C;  // ','
            6'd31: rom_byte = 8'h30;  // '0'
            6'd32: rom_byte = 8'h0D;  // CR
            6'd33: rom_byte = 8'h0A;  // LF
            default: rom_byte = 8'h00;
            endcase
        end
    endfunction

    // ---- 接收侧：复用本分支的 uart_rx，波特率同为 38400 ----
    wire [7:0] rx_byte;
    wire       rx_valid;

    uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) u_rx (
        .clk  (clk),
        .rst_n(rst_n),
        .rx   (at_rx),
        .data (rx_byte),
        .valid(rx_valid)
    );

    // ---- 应答识别：连续两个字节是 'O''K' 即判定收到 OK ----
    reg [7:0] prev_byte;
    reg       ok_seen;      // 本轮命令的 OK（每发一条命令前清）
    reg       any_seen;     // 曾经收到过任何字节（诊断用）
    reg       got_ok_ever;  // 曾经成功过一次（指示灯用）

    // ---- 发送侧：位转发器 ----
    reg [9:0]  tx_sh;       // {停止位, d7..d0, 起始位}
    reg [10:0] tx_div;
    reg [3:0]  tx_bit;

    // ---- 流程状态 ----
    localparam [2:0] S_BOOT     = 3'd0,
                     S_TX_START = 3'd1,
                     S_TX_SHIFT = 3'd2,
                     S_TX_DONE  = 3'd3,
                     S_WAIT     = 3'd4,
                     S_GAP      = 3'd5,
                     S_FIN      = 3'd6,
                     S_ERR      = 3'd7;

    reg [2:0]  state;
    reg [1:0]  cmd_idx;
    reg [5:0]  byte_idx;
    reg [3:0]  retry;
    reg [31:0] cyc;

    // 当前命令的起始偏移与长度
    wire [5:0] flat = (cmd_idx == 2'd0) ? byte_idx :
                      (cmd_idx == 2'd1) ? (6'd4  + byte_idx) :
                                          (6'd14 + byte_idx);
    wire [5:0] clen = (cmd_idx == 2'd0) ? 6'd4  :
                      (cmd_idx == 2'd1) ? 6'd10 : 6'd20;

    // ---- 心跳与快闪 ----
    reg [24:0] hb;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) hb <= 25'd0;
        else        hb <= hb + 25'd1;
    end
    wire slow_blink = hb[24];   // 半周期 0.62 s
    wire fast_blink = hb[21];   // 半周期 78 ms

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_BOOT;
            at_tx       <= 1'b1;
            done        <= 1'b0;
            fail        <= 1'b0;
            cmd_idx     <= 2'd0;
            byte_idx    <= 6'd0;
            retry       <= 4'd0;
            cyc         <= 32'd0;
            tx_sh       <= 10'h3FF;
            tx_div      <= 11'd0;
            tx_bit      <= 4'd0;
            prev_byte   <= 8'h00;
            ok_seen     <= 1'b0;
            any_seen    <= 1'b0;
            got_ok_ever <= 1'b0;
        end else begin
            // ---------- 接收与应答识别（与状态机并行） ----------
            if (rx_valid) begin
                any_seen <= 1'b1;
                if (prev_byte == 8'h4F && rx_byte == 8'h4B) begin
                    ok_seen     <= 1'b1;
                    got_ok_ever <= 1'b1;
                end
                prev_byte <= rx_byte;
            end

            // ---------- 主状态机 ----------
            case (state)
            S_BOOT: begin
                at_tx <= 1'b1;
                if (cyc >= BOOT_C - 32'd1) begin
                    cyc     <= 32'd0;
                    byte_idx <= 6'd0;
                    state   <= S_TX_START;
                end else begin
                    cyc <= cyc + 32'd1;
                end
            end

            S_TX_START: begin
                tx_sh   <= {1'b1, rom_byte(flat), 1'b0};
                at_tx   <= 1'b0;            // 起始位
                tx_div  <= BIT_C - 11'd1;
                tx_bit  <= 4'd0;
                state   <= S_TX_SHIFT;
            end

            S_TX_SHIFT: begin
                if (tx_div == 11'd0) begin
                    if (tx_bit == 4'd9) begin
                        at_tx <= 1'b1;      // 停止位发完，回空闲
                        state <= S_TX_DONE;
                    end else begin
                        tx_sh  <= {1'b1, tx_sh[9:1]};
                        at_tx  <= tx_sh[1];
                        tx_bit <= tx_bit + 4'd1;
                        tx_div <= BIT_C - 11'd1;
                    end
                end else begin
                    tx_div <= tx_div - 11'd1;
                end
            end

            S_TX_DONE: begin
                at_tx <= 1'b1;
                if (byte_idx + 6'd1 < clen) begin
                    byte_idx <= byte_idx + 6'd1;
                    state    <= S_TX_START;
                end else begin
                    cyc   <= 32'd0;
                    state <= S_WAIT;
                end
            end

            S_WAIT: begin
                if (ok_seen) begin
                    ok_seen   <= 1'b0;
                    prev_byte <= 8'h00;
                    retry     <= 4'd0;
                    cyc       <= 32'd0;
                    byte_idx  <= 6'd0;
                    if (cmd_idx == 2'd2) begin
                        done  <= 1'b1;
                        state <= S_FIN;
                    end else begin
                        cmd_idx <= cmd_idx + 2'd1;
                        state   <= S_GAP;
                    end
                end else if (cyc >= TMO_C - 32'd1) begin
                    cyc       <= 32'd0;
                    ok_seen   <= 1'b0;
                    prev_byte <= 8'h00;
                    byte_idx  <= 6'd0;
                    if (retry == RTY_C - 4'd1) begin
                        fail  <= 1'b1;
                        state <= S_ERR;
                    end else begin
                        retry <= retry + 4'd1;
                        state <= S_GAP;
                    end
                end else begin
                    cyc <= cyc + 32'd1;
                end
            end

            S_GAP: begin
                if (cyc >= GAP_C - 32'd1) begin
                    cyc   <= 32'd0;
                    state <= S_TX_START;
                end else begin
                    cyc <= cyc + 32'd1;
                end
            end

            S_FIN: begin
                at_tx <= 1'b1;
                done  <= 1'b1;
            end

            S_ERR: begin
                at_tx <= 1'b1;
                fail  <= 1'b1;
            end

            default: state <= S_ERR;
            endcase
        end
    end

    // ---- 指示灯 ----
    // [0] 心跳    [1] 正在发送   [2] 收到过数据
    // [3] 收到过 OK   [4] 成功    [5] 失败（快闪）
    always @(*) begin
        led[0] = slow_blink;
        led[1] = (state == S_TX_START) || (state == S_TX_SHIFT) || (state == S_TX_DONE);
        led[2] = any_seen;
        led[3] = got_ok_ever;
        led[4] = done;
        led[5] = fail & fast_blink;
    end

endmodule
`default_nettype wire
