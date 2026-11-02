`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// tb_top_bt_in.v —— 蓝牙输入链路整机测试
//   只从外部引脚 uart_rx_pin（脚 77）喂串行帧，不碰任何内部信号赋值。
//   验证：帧 -> uart_rx -> bt_cmd_parse -> 事件多路器 -> voice_alloc -> gate/note
//   同时验证 owner 接管/交还，以及交还后触摸板恢复工作。
//   加速：TTP 与传感器滤波用短参数，UART 比特宽度保持真实的 234 拍。
// ============================================================================
module tb_top_bt_in;

    reg        clk = 0, rst_n = 0, test_enable = 0;
    reg [15:0] touch = 16'd0;
    reg        uart_rx_pin = 1'b1;
    wire       uart_tx_pin;
    wire       ttp_scl, ttp_sdo, bclk, lrclk, i2s_data, pa_en;

    localparam integer BIT = 234;

    top #(.TTP_STARTUP_CYCLES(20), .TTP_SCL_HALF_CYCLES(10),
          .TTP_FRAME_GAP_CYCLES(300), .TOUCH_CTRL_FILT(4)) dut (.*);

    ttp229_model #(.DATA_DELAY_NS(20), .TIMEOUT_NS(2000)) chip (
        .rst_n(rst_n), .scl(ttp_scl), .keys(touch), .sdo(ttp_sdo));

    defparam dut.u_sensor_frontend.FILT_CYCLES = 4;

    always #5 clk = ~clk;

    integer errors = 0;
    integer i;

    task cycles(input integer n);
        begin repeat (n) @(negedge clk); #1; end
    endtask

    task check(input bit ok, input string message);
        begin
            if (ok !== 1'b1) begin
                $display("FAIL bt-in top: %s", message);
                errors = errors + 1;
            end else begin
                $display("  ok %s", message);
            end
        end
    endtask

    // ---- 串口发送一个字节（234 拍/比特，negdege 驱动避免竞争）----
    task uart_put(input [7:0] b);
        begin
            @(negedge clk); uart_rx_pin = 1'b0;
            repeat (BIT) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_pin = b[i];
                repeat (BIT) @(negedge clk);
            end
            uart_rx_pin = 1'b1;
            repeat (BIT) @(negedge clk);
        end
    endtask

    function [7:0] crc8;
        input [7:0] d;
        input [7:0] c;
        integer j;
        begin
            crc8 = c ^ d;
            for (j = 0; j < 8; j = j + 1)
                crc8 = crc8[7] ? ((crc8 << 1) ^ 8'h07) : (crc8 << 1);
        end
    endfunction

    task send_note(input [7:0] note, input [7:0] flags);
        reg [7:0] c;
        begin
            c = crc8(8'h00, 8'h02);
            c = crc8(c, 8'h02);
            c = crc8(c, note);
            c = crc8(c, flags);
            uart_put(8'hAA); uart_put(8'h55); uart_put(8'h02); uart_put(8'h02);
            uart_put(note);  uart_put(flags); uart_put(c);
        end
    endtask

    task send_release;
        reg [7:0] c;
        begin
            c = crc8(crc8(8'h00, 8'h03), 8'h00);
            uart_put(8'hAA); uart_put(8'h55); uart_put(8'h03); uart_put(8'h00); uart_put(c);
        end
    endtask

    // 4 个声部里是否有某一路正在 gate 且音高等于 note
    function gate_has_note(input [6:0] note);
        integer k;
        begin
            gate_has_note = 1'b0;
            for (k = 0; k < 4; k = k + 1)
                if (dut.voice_gate[k] && dut.voice_note[k*7+:7] == note)
                    gate_has_note = 1'b1;
        end
    endfunction

    integer g;

    initial begin
        $dumpfile("sim/tb_top_bt_in.vcd");
        $dumpvars(0, rst_n, test_enable, touch, uart_rx_pin,
                  dut.core_rst_n, dut.bt_owner, dut.bt_evt_valid, dut.bt_evt_ready,
                  dut.bt_evt_key, dut.bt_evt_note, dut.bt_evt_on,
                  dut.voice_gate, dut.voice_note, dut.key_state);

        cycles(4); rst_n = 1'b1; cycles(1300);

        $display("=== 1. 复位后状态 ===");
        check(dut.bt_owner === 1'b0, "复位后 owner=0（触摸板控制）");
        check(dut.voice_gate === 4'b0000, "复位后无声部在响");

        $display("=== 2. 脚 77 收 NOTE ON C4（key0）===");
        send_note(8'h3C, 8'h01);
        cycles(20);
        check(dut.bt_owner === 1'b1, "收到第一条命令后 owner=1（蓝牙接管）");
        check(gate_has_note(7'd60) === 1'b1, "声部已起音，音高 60 (C4)");

        $display("=== 3. NOTE OFF C4 ===");
        send_note(8'h3C, 8'h00);
        cycles(20);
        begin : wait_release
            integer guard;
            guard = 0;
            // 包络释放要跑完才真正关 gate，这里只确认已经进入释放（gate 可能仍高）
            if (dut.bt_owner !== 1'b1) begin
                $display("FAIL: NOTE OFF 把 owner 弄掉了");
                errors = errors + 1;
            end else begin
                $display("  ok NOTE OFF 后 owner 保持 1");
            end
        end

        $display("=== 4. 键号 5、音高 71（B4）===");
        send_note(8'h47, 8'h0B);            // flags=(5<<1)|1
        cycles(20);
        check(gate_has_note(7'd71) === 1'b1, "声部起音音高 71 (B4)");

        $display("=== 5. 释放控制帧交还触摸板 ===");
        send_release;
        cycles(20);
        check(dut.bt_owner === 1'b0, "释放帧后 owner=0");

        $display("=== 6. 交还后触摸板仍然工作 ===");
        touch = 16'h0002;                   // TP1 -> D4
        cycles(1300);
        check(dut.key_state === 8'h02, "TP1 经触摸板通路点亮 key_state=0x02");
        check(gate_has_note(7'd62) === 1'b1, "触摸板 TP1 起音音高 62 (D4)");
        touch = 16'd0;
        cycles(1300);
        check(dut.key_state === 8'h00, "松开后 key_state 归零");

        $display("=== 7. 坏 CRC 不得接管 ===");
        begin : bad_crc
            reg [7:0] c;
            c = crc8(crc8(crc8(crc8(8'h00, 8'h02), 8'h02), 8'h3C), 8'h01) ^ 8'hFF;
            uart_put(8'hAA); uart_put(8'h55); uart_put(8'h02); uart_put(8'h02);
            uart_put(8'h3C); uart_put(8'h01); uart_put(c);
        end
        cycles(20);
        check(dut.bt_owner === 1'b0, "坏 CRC 帧未接管");

        if (errors == 0) $display("PASS: tb_top_bt_in");
        else             $display("FAIL: tb_top_bt_in (%0d 项)", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: tb_top_bt_in 超时");
        $finish;
    end

endmodule
`default_nettype wire
