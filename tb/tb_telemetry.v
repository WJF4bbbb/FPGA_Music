`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// tb_telemetry.v —— telemetry 自检
//
// 做法：喂一组固定输入，等一帧发出，从 tx 波形把 20 字节全解出来，
// 逐字段比对，最后自己算一遍 CRC 和帧里的比对。
//
// 覆盖：帧头、长度、每个数据字段、符号扩展（bend = -2）、CRC
// ============================================================================
module tb_telemetry;

    localparam integer CLK_HZ = 27000000;
    localparam integer BAUD   = 115200;
    localparam integer DIV    = CLK_HZ / BAUD;   // 234
    localparam integer SNAP_DIV = CLK_HZ / 30;   // 900000

    reg clk = 0;
    reg rst_n = 0;

    // ---- 固定测试向量 ----
    reg [15:0]         keys   = 16'h0005;              // TP0 + TP2 按下
    reg [27:0]         notes  = {7'd72, 7'd67, 7'd64, 7'd60};
    reg [3:0]          gates  = 4'b0101;               // 声部 0 和 2 在响
    reg [1:0]          timbre = 2'd2;                  // 锯齿
    reg signed [3:0]   bend   = -4'sd2;                // 弯音 -2 半音
    reg [15:0]         gain   = 16'd49152;             // 0.75
    reg [31:0]         clip   = 32'd7;

    wire tx, tx_busy;

    integer errors = 0;
    reg [7:0] frame [0:19];
    integer i;

    telemetry #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .NVOICE(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .touch_keys(keys), .voice_note(notes), .voice_gate(gates),
        .timbre(timbre), .bend(bend), .master_gain(gain), .clip_count(clip),
        .sample(16'sd0), .sample_valid(1'b0),
        .tx(tx), .tx_busy(tx_busy)
    );

    always #18.518518518 clk = ~clk;

    // ---- 调试监视 ----
    always @(posedge clk) begin
        if (dut.snap_pulse) $display("  [dbg] SNAP  t=%0t  tick=%0d", $time, dut.tick);
        if (dut.tx_send)    $display("  [dbg] SEND  byte_idx=%0d data=0x%02h", dut.byte_idx, dut.tx_data);
    end

    // ---- CRC8 参考实现（独立于 DUT，用来验算） ----
    function [7:0] ref_crc8;
        input [7:0] d;
        input [7:0] c;
        integer k;
        reg [7:0] x;
        begin
            x = c ^ d;
            for (k = 0; k < 8; k = k + 1)
                x = x[7] ? ((x << 1) ^ 8'h07) : (x << 1);
            ref_crc8 = x;
        end
    endfunction

    task fail(input [511:0] msg);
        begin
            errors = errors + 1;
            $display("  FAIL: %0s", msg);
        end
    endtask

    // ---- 独立接收端：按 8N1 时序解一个字节 ----
    task recv_byte(output [7:0] got);
        integer k;
        begin
            got = 8'h00;
            @(negedge tx);
            repeat (DIV/2) @(posedge clk);
            if (tx !== 1'b0) fail("start bit not low");
            for (k = 0; k < 8; k = k + 1) begin
                repeat (DIV) @(posedge clk);
                got[k] = tx;
            end
            repeat (DIV) @(posedge clk);
            if (tx !== 1'b1) fail("stop bit not high");
        end
    endtask

    // ---- 逐字段检查 ----
    reg [7:0] crc_calc;

    task check_frame;
        begin
            if (frame[0] !== 8'hAA) fail("head0 != AA");
            if (frame[1] !== 8'h55) fail("head1 != 55");
            if (frame[2] !== 8'h01) fail("type != 01");
            if (frame[3] !== 8'h0F) fail("len != 0F");

            if ({frame[5],  frame[4]}  !== keys)  fail("touch_keys mismatch");
            if (frame[6]  !== 8'd60) fail("voice0 note mismatch");
            if (frame[7]  !== 8'd64) fail("voice1 note mismatch");
            if (frame[8]  !== 8'd67) fail("voice2 note mismatch");
            if (frame[9]  !== 8'd72) fail("voice3 note mismatch");
            if (frame[10] !== 8'h05) fail("gates mismatch");
            if (frame[11] !== 8'h02) fail("timbre mismatch");
            if (frame[12] !== 8'hFE) fail("bend sign-extend mismatch (want FE)");
            if ({frame[14], frame[13]} !== gain) fail("master_gain mismatch");
            if ({frame[18], frame[17], frame[16], frame[15]} !== clip) fail("clip_count mismatch");

            // 独立算一遍 CRC，覆盖 frame[2..18]
            crc_calc = 8'h00;
            for (i = 2; i <= 18; i = i + 1)
                crc_calc = ref_crc8(frame[i], crc_calc);
            if (frame[19] !== crc_calc) begin
                $display("  FAIL: CRC mismatch, got 0x%02h want 0x%02h", frame[19], crc_calc);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("=== tb_telemetry: %0d Hz / %0d baud / 快照周期 %0d 拍 ===",
                 CLK_HZ, BAUD, SNAP_DIV);

        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;

        // 提前 200 拍就位，确保第一个字节的起始位下降沿不被错过
        repeat (SNAP_DIV - 200) @(posedge clk);

        // 连续解 20 个字节
        for (i = 0; i < 20; i = i + 1)
            recv_byte(frame[i]);

        $display("  收到 20 字节：");
        $display("    %02h %02h %02h %02h | %02h %02h | %02h %02h %02h %02h",
                 frame[0], frame[1], frame[2], frame[3],
                 frame[4], frame[5], frame[6], frame[7], frame[8], frame[9]);
        $display("    %02h %02h %02h | %02h %02h | %02h %02h %02h %02h | %02h",
                 frame[10], frame[11], frame[12],
                 frame[13], frame[14],
                 frame[15], frame[16], frame[17], frame[18], frame[19]);

        check_frame;

        $display("");
        if (errors == 0) $display("ALL PASS");
        else             $display("FAILED  %0d 个错误", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("FAILED  仿真超时（50 ms）");
        $finish;
    end

endmodule
`default_nettype wire
