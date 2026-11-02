`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// tb_bt_at_init.v —— AT 配置模块的端到端仿真
//
// 【测什么】
//   阶段 A：TB 扮演 HC-05，收到 DUT 的每一行命令就回 "OK\r\n"。
//           要求 DUT 把三条命令一个字节不差地发出来，并且 done 拉高。
//   阶段 B：TB 完全不回应（模拟模块没接 / 没进 AT 模式）。
//           要求 DUT 重试 RETRY_MAX 次后置 fail，而不是死等。
//
// 【为什么要解码 TX】
//   只看 done 不够——VCD 里没人肉眼核对字节。这里用一只 uart_rx 把
//   DUT 的 at_tx 解回字节，再和期望字符串逐字节比对，波特率错了必然报错。
// ============================================================================
module tb_bt_at_init;

    reg clk = 1'b0;
    always #18.5 clk = ~clk;          // 27 MHz

    reg  rst_n = 1'b0;
    reg  at_rx = 1'b1;
    wire at_tx;
    wire [5:0] led;
    wire done, fail;

    // 把等待时间压小，只为跑得快；波特率保持真实的 38400
    bt_at_init #(
        .BOOT_MS   (2),
        .TIMEOUT_MS(3),
        .GAP_MS    (1),
        .RETRY_MAX (3)
    ) dut (
        .clk  (clk),
        .rst_n(rst_n),
        .at_tx(at_tx),
        .at_rx(at_rx),
        .led  (led),
        .done (done),
        .fail (fail)
    );

    // ---- 解码 DUT 发出的字节 ----
    wire [7:0] cap_byte;
    wire       cap_valid;

    uart_rx #(
        .CLK_HZ(27000000),
        .BAUD  (38400)
    ) u_dec (
        .clk  (clk),
        .rst_n(rst_n),
        .rx   (at_tx),
        .data (cap_byte),
        .valid(cap_valid)
    );

    reg [7:0] cap [0:127];
    integer   cap_n = 0;
    reg       reply_on = 1'b1;

    always @(posedge clk) begin
        if (cap_valid) begin
            cap[cap_n] = cap_byte;
            cap_n      = cap_n + 1;
        end
    end

    // ---- TB 侧的发送器：模拟模块回 OK ----
    localparam integer BIT = 703;     // 27000000 / 38400 四舍五入

    task send_byte;
        input [7:0] b;
        integer i;
        begin
            at_rx = 1'b0;                          // 起始位
            repeat (BIT) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                at_rx = b[i];
                repeat (BIT) @(negedge clk);
            end
            at_rx = 1'b1;                          // 停止位
            repeat (BIT) @(negedge clk);
        end
    endtask

    always @(posedge clk) begin
        if (reply_on && cap_valid && cap_byte == 8'h0A) begin
            send_byte(8'h4F);   // 'O'
            send_byte(8'h4B);   // 'K'
            send_byte(8'h0D);
            send_byte(8'h0A);
        end
    end

    // ---- 期望的命令流 ----
    // 注意：Verilog 字符串不支持 "\r" 转义（标准只有 \n \t \\ \" 和八进制），
    // "AT\r\n" 会被解析成 'A','T','r',LF —— 所以这里必须写显式十六进制。
    localparam [8*34-1:0] EXPECT = {
        8'h41, 8'h54, 8'h0D, 8'h0A,                                          // "AT\r\n"
        8'h41, 8'h54, 8'h2B, 8'h55, 8'h41, 8'h52, 8'h54, 8'h3F, 8'h0D, 8'h0A, // "AT+UART?\r\n"
        8'h41, 8'h54, 8'h2B, 8'h55, 8'h41, 8'h52, 8'h54, 8'h3D,              // "AT+UART="
        8'h31, 8'h31, 8'h35, 8'h32, 8'h30, 8'h30, 8'h2C, 8'h30, 8'h2C, 8'h30, // "115200,0,0"
        8'h0D, 8'h0A                                                         // "\r\n"
    };

    integer i;
    integer errs = 0;
    integer n_a;

    initial begin
        repeat (10) @(negedge clk);
        rst_n = 1'b1;

        // ================= 阶段 A =================
        for (i = 0; i < 2000000 && !done; i = i + 1) @(posedge clk);
        n_a = cap_n;

        if (!done) begin
            $display("[FAIL] 阶段A：等 done 超时，只收到 %0d 字节", cap_n);
            errs = errs + 1;
        end else begin
            $display("[ OK ] 阶段A：done 拉高，仿真时间 %0d us", $time/1000);
        end

        if (n_a != 34) begin
            $display("[FAIL] 阶段A：字节数 %0d，期望 34", n_a);
            errs = errs + 1;
        end

        for (i = 0; i < 34; i = i + 1) begin
            if (cap[i] !== EXPECT[(33-i)*8 +: 8]) begin
                $display("[FAIL] 阶段A：第 %0d 字节 0x%02h，期望 0x%02h",
                         i, cap[i], EXPECT[(33-i)*8 +: 8]);
                errs = errs + 1;
            end
        end

        $write("[ ok ] 实际发出: \"");
        for (i = 0; i < n_a; i = i + 1) begin
            if (cap[i] == 8'h0D)      $write("\\r");
            else if (cap[i] == 8'h0A) $write("\\n");
            else                      $write("%c", cap[i]);
        end
        $write("\"\n");

        // ================= 阶段 B =================
        reply_on = 1'b0;
        rst_n    = 1'b0;
        repeat (10) @(negedge clk);
        rst_n = 1'b1;

        for (i = 0; i < 3000000 && !fail; i = i + 1) @(posedge clk);

        if (!fail) begin
            $display("[FAIL] 阶段B：模块无应答时应置 fail，但没有");
            errs = errs + 1;
        end else begin
            $display("[ OK ] 阶段B：无应答，重试 %0d 次后 fail 拉高（未死等）", 3);
        end

        if (errs == 0) $display("\n=== ALL PASS ===");
        else           $display("\n=== %0d FAILURES ===", errs);

        $finish;
    end

endmodule
`default_nettype wire
