`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// tb_uart_rx.v —— uart_rx 自检
//   1) 逐字节收发（0x55 / 0xAA / 0x00 / 0xFF / 0x3C / 0xA5）
//   2) 背靠背连续字节（停止位后直接起始位，无空闲间隔）
//   3) 短毛刺不得被当成起始位
//   4) 停止位为低（帧错误）时整字节丢弃
// 波特率模型：234 拍/比特，与 27 MHz / 115200 一致。
// ============================================================================
module tb_uart_rx;

    localparam integer BIT = 234;

    reg        clk   = 1'b0;
    reg        rst_n = 1'b0;
    reg        rx    = 1'b1;
    wire [7:0] data;
    wire       valid;

    integer errors = 0;
    integer nrecv  = 0;
    integer k;
    reg [7:0] got [0:31];

    // 100 MHz 仿真时钟；分频值由参数固定为 234，与真实时钟频率无关
    always #5 clk = ~clk;

    uart_rx #(.CLK_HZ(27000000), .BAUD(115200)) dut (
        .clk(clk), .rst_n(rst_n), .rx(rx), .data(data), .valid(valid)
    );

    always @(posedge clk) begin
        if (valid) begin
            got[nrecv] = data;
            nrecv      = nrecv + 1;
            $display("  rx byte %02X @ %0t", data, $time);
        end
    end

    // ---- 发送一个字节（8N1），起始位低、LSB first、停止位高 ----
    // 在 negedge 改变 rx，避免与 DUT 的 posedge 采样同拍竞争
    task send_byte(input [7:0] b);
        integer i;
        begin
            @(negedge clk); rx = 1'b0;
            repeat (BIT) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];
                repeat (BIT) @(negedge clk);
            end
            rx = 1'b1;
            repeat (BIT) @(negedge clk);
        end
    endtask

    // ---- 发送一个停止位被拉低的坏字节（模拟波特率不符/干扰）----
    task send_bad_byte(input [7:0] b);
        integer i;
        begin
            @(negedge clk); rx = 1'b0;
            repeat (BIT) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];
                repeat (BIT) @(negedge clk);
            end
            rx = 1'b0;                  // 停止位故意为低
            repeat (BIT) @(negedge clk);
            rx = 1'b1;
            repeat (4) @(negedge clk);
        end
    endtask

    task check(input [7:0] exp, input [255:0] tag);
        begin
            if (nrecv == 0) begin
                $display("FAIL: %0s 没有收到字节", tag);
                errors = errors + 1;
            end else if (got[nrecv-1] !== exp) begin
                $display("FAIL: %0s 收到 %02X，期望 %02X", tag, got[nrecv-1], exp);
                errors = errors + 1;
            end else begin
                $display("  ok %0s = %02X", tag, exp);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        $display("=== 1. 逐字节 ===");
        send_byte(8'h55); check(8'h55, "0x55");
        send_byte(8'hAA); check(8'hAA, "0xAA");
        send_byte(8'h00); check(8'h00, "0x00");
        send_byte(8'hFF); check(8'hFF, "0xFF");
        send_byte(8'h3C); check(8'h3C, "0x3C (C4)");
        send_byte(8'hA5); check(8'hA5, "0xA5");

        $display("=== 2. 背靠背连续字节 ===");
        begin : back_to_back
            nrecv = 0;
            for (k = 0; k < 4; k = k + 1) send_byte(8'h10 + k[7:0]);
            repeat (20) @(posedge clk);
            if (nrecv != 4) begin
                $display("FAIL: 背靠背只收到 %0d 字节，期望 4", nrecv);
                errors = errors + 1;
            end else if (got[0] !== 8'h10 || got[1] !== 8'h11 ||
                         got[2] !== 8'h12 || got[3] !== 8'h13) begin
                $display("FAIL: 背靠背数据错 %02X %02X %02X %02X",
                         got[0], got[1], got[2], got[3]);
                errors = errors + 1;
            end else begin
                $display("  ok 背靠背 4 字节 10 11 12 13");
            end
        end

        $display("=== 3. 短毛刺不得误触发 ===");
        begin : glitch
            nrecv = 0;
            @(negedge clk); rx = 1'b0;      // 只低 20 拍，远小于半比特 117 拍
            repeat (20) @(negedge clk);
            rx = 1'b1;
            repeat (400) @(posedge clk);
            if (nrecv != 0) begin
                $display("FAIL: 毛刺产生了 %0d 个字节", nrecv);
                errors = errors + 1;
            end else begin
                $display("  ok 毛刺被忽略");
            end
        end

        $display("=== 4. 停止位为低：帧错误丢弃 ===");
        begin : frame_error
            nrecv = 0;
            send_bad_byte(8'h5A);
            repeat (400) @(posedge clk);
            if (nrecv != 0) begin
                $display("FAIL: 帧错误字节被接收（%02X）", got[0]);
                errors = errors + 1;
            end else begin
                $display("  ok 帧错误字节被丢弃");
            end
        end

        $display("=== 5. 帧错误后仍能正常接收 ===");
        begin : recover
            nrecv = 0;
            send_bad_byte(8'h11);
            repeat (6 * BIT) @(negedge clk);   // 先让线路回到空闲高，再发正常帧
            send_byte(8'h42);
            repeat (20) @(posedge clk);
            if (nrecv != 1 || got[0] !== 8'h42) begin
                $display("FAIL: 帧错误后恢复失败，nrecv=%0d", nrecv);
                errors = errors + 1;
            end else begin
                $display("  ok 帧错误后下一字节正常");
            end
        end

        if (errors == 0) $display("PASS: tb_uart_rx");
        else             $display("FAIL: tb_uart_rx (%0d 项)", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: tb_uart_rx 超时");
        $finish;
    end

endmodule
`default_nettype wire
