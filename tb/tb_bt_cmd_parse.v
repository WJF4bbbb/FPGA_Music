`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// tb_bt_cmd_parse.v —— 蓝牙命令解析自检
//   1) CRC8 标准答案（docs/BT_LINK_SPLIT.md 第 6.3 节）
//   2) 合法 NOTE ON / NOTE OFF，键号与音高正确，owner 拉高
//   3) CRC 错误必须丢弃且不改变 owner
//   4) 帧前粘垃圾字节仍能重同步
//   5) 连续快速按键，每个事件都被 voice_alloc 收走（握手不丢）
//   6) 释放控制帧（type=03）把 owner 拉低
//   7) 长度非法（>8）丢弃
//   8) 未知类型帧校验通过也不产生事件
// ============================================================================
module tb_bt_cmd_parse;

    reg        clk   = 1'b0;
    reg        rst_n = 1'b0;
    reg  [7:0] data  = 8'd0;
    reg        valid = 1'b0;
    wire       evt_valid;
    wire [2:0] evt_key_id;
    wire [6:0] evt_note;
    wire       evt_on;
    wire       owner;

    reg        evt_ready = 1'b1;      // voice_alloc 的 evt_ready 恒为 1

    integer errors = 0;
    integer nev    = 0;
    reg [2:0] cap_key  [0:15];
    reg [6:0] cap_note [0:15];
    reg       cap_on   [0:15];

    always #5 clk = ~clk;

    bt_cmd_parse dut (
        .clk(clk), .rst_n(rst_n),
        .data(data), .valid(valid),
        .evt_valid(evt_valid), .evt_ready(evt_ready),
        .evt_key_id(evt_key_id), .evt_note(evt_note), .evt_on(evt_on),
        .owner(owner)
    );

    // 只在 evt_valid 与 evt_ready 同时为高那拍才算送达
    always @(posedge clk) begin
        if (evt_valid && evt_ready) begin
            cap_key[nev]  = evt_key_id;
            cap_note[nev] = evt_note;
            cap_on[nev]   = evt_on;
            nev = nev + 1;
        end
    end

    function [7:0] crc8;
        input [7:0] d;
        input [7:0] c;
        integer i;
        begin
            crc8 = c ^ d;
            for (i = 0; i < 8; i = i + 1)
                crc8 = crc8[7] ? ((crc8 << 1) ^ 8'h07) : (crc8 << 1);
        end
    endfunction

    task put(input [7:0] b);
        begin
            @(negedge clk);
            data  = b;
            valid = 1'b1;
            @(negedge clk);
            valid = 1'b0;
        end
    endtask

    task send_note(input [7:0] note, input [7:0] flags);
        reg [7:0] c;
        begin
            c = crc8(8'h00, 8'h02);
            c = crc8(c, 8'h02);
            c = crc8(c, note);
            c = crc8(c, flags);
            put(8'hAA); put(8'h55); put(8'h02); put(8'h02);
            put(note);  put(flags); put(c);
        end
    endtask

    task send_release;
        reg [7:0] c;
        begin
            c = crc8(crc8(8'h00, 8'h03), 8'h00);
            put(8'hAA); put(8'h55); put(8'h03); put(8'h00); put(c);
        end
    endtask

    initial begin
        $dumpfile("sim/tb_bt_cmd_parse.vcd");
        $dumpvars(0, tb_bt_cmd_parse);

        $display("=== 1. CRC8 标准答案 ===");
        if (crc8(crc8(8'h00, 8'h01), 8'h0F) !== 8'h38) begin
            $display("FAIL: crc8(01 0F) = %02X, 期望 38", crc8(crc8(8'h00, 8'h01), 8'h0F));
            errors = errors + 1;
        end else $display("  ok crc8(01 0F) = 38");

        if (crc8(crc8(crc8(crc8(8'h00, 8'h02), 8'h02), 8'h3C), 8'h01) !== 8'hF8) begin
            $display("FAIL: crc8(02 02 3C 01) != F8");
            errors = errors + 1;
        end else $display("  ok crc8(02 02 3C 01) = F8");

        if (crc8(crc8(8'h00, 8'h03), 8'h00) !== 8'h3F) begin
            $display("FAIL: crc8(03 00) != 3F");
            errors = errors + 1;
        end else $display("  ok crc8(03 00) = 3F");

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        $display("=== 2. NOTE ON / OFF ===");
        nev = 0;
        send_note(8'h3C, 8'h01);                 // C4, key0, on
        repeat (4) @(posedge clk);
        if (nev != 1) begin
            $display("FAIL: NOTE ON 产生 %0d 个事件，期望 1", nev); errors = errors + 1;
        end else if (cap_note[0] !== 7'h3C || cap_key[0] !== 3'd0 || cap_on[0] !== 1'b1) begin
            $display("FAIL: NOTE ON 内容错 note=%02X key=%0d on=%0d",
                     cap_note[0], cap_key[0], cap_on[0]); errors = errors + 1;
        end else if (owner !== 1'b1) begin
            $display("FAIL: 收到第一条命令后 owner 仍为 0"); errors = errors + 1;
        end else $display("  ok NOTE ON  note=3C key=0 on=1, owner=1");

        nev = 0;
        send_note(8'h3C, 8'h00);                 // C4, key0, off
        repeat (4) @(posedge clk);
        if (nev != 1 || cap_on[0] !== 1'b0) begin
            $display("FAIL: NOTE OFF 错 nev=%0d on=%0d", nev, cap_on[0]); errors = errors + 1;
        end else $display("  ok NOTE OFF on=0");

        $display("=== 3. 键号 5（flags=0x0B）===");
        nev = 0;
        send_note(8'h47, 8'h0B);                 // B4, key5, on
        repeat (4) @(posedge clk);
        if (nev != 1 || cap_key[0] !== 3'd5 || cap_note[0] !== 7'h47) begin
            $display("FAIL: key5 解析错 nev=%0d key=%0d note=%02X", nev, cap_key[0], cap_note[0]);
            errors = errors + 1;
        end else $display("  ok key=5 note=47");

        $display("=== 4. CRC 错误必须丢弃 ===");
        nev = 0;
        put(8'hAA); put(8'h55); put(8'h02); put(8'h02);
        put(8'h3C); put(8'h01); put(8'h00);      // 故意错 CRC
        repeat (4) @(posedge clk);
        if (nev != 0) begin
            $display("FAIL: 坏 CRC 仍产生了 %0d 个事件", nev); errors = errors + 1;
        end else if (owner !== 1'b1) begin
            $display("FAIL: 坏 CRC 把 owner 弄错了"); errors = errors + 1;
        end else $display("  ok 坏 CRC 丢弃，owner 保持 1");

        $display("=== 5. 帧前粘垃圾字节仍能解析 ===");
        nev = 0;
        put(8'h00); put(8'h12); put(8'hAA); put(8'h33);   // AA 33 是假帧头
        send_note(8'h40, 8'h03);                          // E4, key1, on
        repeat (4) @(posedge clk);
        if (nev != 1 || cap_note[0] !== 7'h40 || cap_key[0] !== 3'd1) begin
            $display("FAIL: 重同步失败 nev=%0d note=%02X key=%0d", nev, cap_note[0], cap_key[0]);
            errors = errors + 1;
        end else $display("  ok 垃圾字节后重同步正常");

        $display("=== 6. 连续快速按键（4 帧背靠背）===");
        nev = 0;
        send_note(8'h3C, 8'h01);
        send_note(8'h3E, 8'h03);
        send_note(8'h40, 8'h05);
        send_note(8'h41, 8'h07);
        repeat (6) @(posedge clk);
        if (nev != 4) begin
            $display("FAIL: 连续 4 帧只收到 %0d 个事件", nev); errors = errors + 1;
        end else if (cap_note[0] !== 7'h3C || cap_note[3] !== 7'h41 ||
                     cap_key[0] !== 3'd0  || cap_key[3] !== 3'd3) begin
            $display("FAIL: 连续帧内容错 %02X/%0d ... %02X/%0d",
                     cap_note[0], cap_key[0], cap_note[3], cap_key[3]); errors = errors + 1;
        end else $display("  ok 4 帧 -> 4 个事件，顺序正确");

        $display("=== 7. 长度非法（len=9）丢弃 ===");
        nev = 0;
        put(8'hAA); put(8'h55); put(8'h02); put(8'h09);
        put(8'h00); put(8'h00); put(8'h00);
        repeat (4) @(posedge clk);
        if (nev != 0) begin
            $display("FAIL: 非法长度仍产生事件"); errors = errors + 1;
        end else $display("  ok 非法长度被丢弃");

        $display("=== 8. 未知类型（03 以外的 0x07）不产生事件 ===");
        nev = 0;
        begin : unknown_type
            reg [7:0] c;
            c = crc8(crc8(8'h00, 8'h07), 8'h01);
            put(8'hAA); put(8'h55); put(8'h07); put(8'h01); put(8'h00); put(c);
        end
        repeat (4) @(posedge clk);
        if (nev != 0) begin
            $display("FAIL: 未知类型产生了事件"); errors = errors + 1;
        end else $display("  ok 未知类型静默忽略");

        $display("=== 9. 释放控制帧把 owner 拉低 ===");
        send_release;
        repeat (4) @(posedge clk);
        if (owner !== 1'b0) begin
            $display("FAIL: 释放帧后 owner 仍为 %0d", owner); errors = errors + 1;
        end else $display("  ok 释放控制 -> owner=0");

        $display("=== 10. 释放后再来音符帧，owner 重新拉高 ===");
        nev = 0;
        send_note(8'h43, 8'h01);
        repeat (4) @(posedge clk);
        if (nev != 1 || owner !== 1'b1) begin
            $display("FAIL: 重新接管失败 nev=%0d owner=%0d", nev, owner); errors = errors + 1;
        end else $display("  ok 重新接管 owner=1");

        if (errors == 0) $display("PASS: tb_bt_cmd_parse");
        else             $display("FAIL: tb_bt_cmd_parse (%0d 项)", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: tb_bt_cmd_parse 超时");
        $finish;
    end

endmodule
`default_nettype wire
