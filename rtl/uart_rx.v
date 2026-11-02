`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// uart_rx.v —— 串口接收（8N1，无流控）
//
// 【负责人】feature/bt-in 分支
// 【状态】已实现
//
// 【端口约定】（冻结，未改动）
//   clk    : 27 MHz 系统时钟（与全设计同域，没有跨时钟）
//   rst_n  : 低有效复位（接 core_rst_n）
//   rx     : 串口输入线，来自 HC-05 的 TXD，空闲时为高
//   data   : 收到的一个字节（8 位）
//   valid  : 单周期脉冲，data 有效的那个时钟拉高一次
//
// 【实现】
//   1. rx 两级同步后再用（外部信号与 27 MHz 不同步，直接采样会有亚稳态）
//   2. 空闲态看到 rx_i 为低 -> 进入起始位，等半个比特到起始位中心
//   3. 起始位中心仍为低才算真起始（否则是毛刺，直接回空闲，不占用一帧）
//   4. 之后每过一个完整比特采一次，采在比特中心（LSB first）
//   5. 停止位中心采样必须为高；为低说明帧错误（波特率不符/线路干扰），
//      丢弃整字节、不拉 valid —— 宁可丢一个字节，也不要把错字节塞给上层
//
// 【分频】27 MHz / 115200 = 234.375，取 234，误差 +0.16%。
//        10 位（起始+8 数据+停止）累计偏差 0.16% x 9.5 < 0.02 比特，
//        采样点仍稳稳落在中心，不需要小数分频。
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
    // 四舍五入取分频值：115200 -> 234
    localparam integer BIT_DIV  = (CLK_HZ + (BAUD / 2)) / BAUD;
    localparam integer HALF_DIV = BIT_DIV / 2;
    localparam integer CNT_W    = 10;

    localparam [CNT_W-1:0] BIT_C  = BIT_DIV;
    localparam [CNT_W-1:0] HALF_C = HALF_DIV;

    localparam [2:0] S_IDLE  = 3'd0,
                     S_START = 3'd1,
                     S_DATA  = 3'd2,
                     S_STOP  = 3'd3;

    reg [1:0]       sync;
    reg [2:0]       state;
    reg [CNT_W-1:0] cnt;
    reg [2:0]       bit_idx;
    reg [7:0]       sh;

    wire rx_i = sync[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync    <= 2'b11;          // 空闲为高
            data    <= 8'd0;
            valid   <= 1'b0;
            state   <= S_IDLE;
            cnt     <= {CNT_W{1'b0}};
            bit_idx <= 3'd0;
            sh      <= 8'd0;
        end else begin
            sync  <= {sync[0], rx};
            valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (!rx_i) begin       // 下降沿 = 可能的起始位
                        state <= S_START;
                        cnt   <= HALF_C;   // 走到起始位中心
                    end
                end

                S_START: begin
                    if (cnt != {CNT_W{1'b0}}) begin
                        cnt <= cnt - 1'b1;
                    end else if (!rx_i) begin   // 中心仍为低：真起始位
                        state   <= S_DATA;
                        cnt     <= BIT_C - 1'b1;
                        bit_idx <= 3'd0;
                    end else begin
                        state   <= S_IDLE;      // 毛刺，丢弃
                    end
                end

                S_DATA: begin
                    if (cnt != {CNT_W{1'b0}}) begin
                        cnt <= cnt - 1'b1;
                    end else begin
                        sh[bit_idx] <= rx_i;    // LSB first
                        cnt         <= BIT_C - 1'b1;
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end
                end

                S_STOP: begin
                    if (cnt != {CNT_W{1'b0}}) begin
                        cnt <= cnt - 1'b1;
                    end else begin
                        state <= S_IDLE;
                        if (rx_i) begin         // 停止位为高：帧完整
                            data  <= sh;
                            valid <= 1'b1;
                        end                     // 为低：帧错误，静默丢弃
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
