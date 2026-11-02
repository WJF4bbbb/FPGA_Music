`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// tb_uart_tx.v —— uart_tx 自检
//
// 做法：发一个字节，用独立的接收逻辑把 tx 波形解回来，比对是否一致。
// 接收端不复用被测代码，完全按 8N1 时序自己采样，避免"错得一样"。
//
// 覆盖：0x00（全低）、0xFF（全高）、0x55/0xAA（交替）、0x3C（真实音符号）
// 检查：起始位必须是低、停止位必须是高、8 个数据位低位先出
// ============================================================================
module tb_uart_tx;

    localparam integer CLK_HZ = 27000000;
    localparam integer BAUD   = 115200;
    localparam integer DIV    = CLK_HZ / BAUD;   // 234

    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] data = 0;
    reg send = 0;
    wire tx, busy;

    integer errors = 0;
    integer cases = 0;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
        .clk(clk), .rst_n(rst_n), .data(data), .send(send),
        .tx(tx), .busy(busy)
    );

    // 27 MHz
    always #18.518518518 clk = ~clk;

    task fail(input [255:0] msg);
        begin
            errors = errors + 1;
            $display("  FAIL: %0s", msg);
        end
    endtask

    // ---- 独立接收端：按 8N1 时序采样 ----
    task recv(output [7:0] got);
        integer i;
        begin
            got = 8'h00;
            @(negedge tx);                      // 等起始位
            repeat (DIV/2) @(posedge clk);      // 移到起始位中心
            if (tx !== 1'b0) fail("起始位不是低电平");
            for (i = 0; i < 8; i = i + 1) begin
                repeat (DIV) @(posedge clk);    // 每 DIV 拍采一次，正好落在位中心
                got[i] = tx;                    // 低位先出
            end
            repeat (DIV) @(posedge clk);
            if (tx !== 1'b1) fail("停止位不是高电平");
        end
    endtask

    // ---- 发送一个字节 ----
    task send_byte(input [7:0] b);
        begin
            @(posedge clk);
            while (busy) @(posedge clk);
            data <= b;
            send <= 1'b1;
            @(posedge clk);
            send <= 1'b0;
        end
    endtask

    // ---- 发一个、收一个、比对 ----
    task one_case(input [7:0] b);
        reg [7:0] got;
        begin
            cases = cases + 1;
            fork
                send_byte(b);
                recv(got);
            join
            if (got !== b) begin
                $display("  FAIL: 发送 0x%02h，收回 0x%02h", b, got);
                errors = errors + 1;
            end else begin
                $display("  ok   发送 0x%02h，收回 0x%02h", b, got);
            end
            repeat (DIV*2) @(posedge clk);      // 帧间隔
        end
    endtask

    initial begin
        $display("=== tb_uart_tx: %0d Hz / %0d baud / DIV=%0d ===", CLK_HZ, BAUD, DIV);

        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        // 空闲时 tx 必须是高
        if (tx !== 1'b1) fail("复位后 tx 不是空闲高电平");

        one_case(8'h00);
        one_case(8'hFF);
        one_case(8'h55);
        one_case(8'hAA);
        one_case(8'h3C);

        $display("");
        if (errors == 0)
            $display("ALL PASS  (%0d 个用例)", cases);
        else
            $display("FAILED  %0d 个错误 / %0d 个用例", errors, cases);
        $finish;
    end

    // 超时保护
    initial begin
        #20_000_000;
        $display("FAILED  仿真超时");
        $finish;
    end

endmodule
`default_nettype wire
