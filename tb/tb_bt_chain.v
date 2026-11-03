`timescale 1ns/1ps
`default_nettype none
// tb_bt_chain.v —— 蓝牙输入链路 + 触摸板事件链 端到端仿真
//   1) 串口字节流 -> uart_rx -> bt_cmd_parse -> 事件多路器 -> voice_alloc
//   2) 触摸板 key_state -> note_event -> 同一多路器 -> voice_alloc
//   3) 随机噪声字节流的误触发率（解释"没按也响"）
module tb_bt_chain;

    localparam integer CLK_HZ = 27000000;
    localparam integer BAUD   = 115200;
    localparam real    BIT_NS = 1.0e9 / BAUD;      // 8680.5 ns

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #18.5185 clk = ~clk;                    // 27 MHz

    // ---------------- 串口接收 ----------------
    reg  uart_rx_pin = 1'b1;
    wire [7:0] bt_data;
    wire       bt_valid;
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx_pin),
        .data(bt_data), .valid(bt_valid)
    );

    // ---------------- 命令解析 ----------------
    wire       bt_evt_valid, bt_evt_ready, bt_evt_on;
    wire [2:0] bt_evt_key;
    wire [6:0] bt_evt_note;
    wire       bt_owner;
    bt_cmd_parse u_parse (
        .clk(clk), .rst_n(rst_n),
        .data(bt_data), .valid(bt_valid),
        .evt_valid(bt_evt_valid), .evt_ready(bt_evt_ready),
        .evt_key_id(bt_evt_key), .evt_note(bt_evt_note), .evt_on(bt_evt_on),
        .owner(bt_owner)
    );

    // ---------------- 触摸板事件 ----------------
    reg  [7:0] key_state = 8'd0;
    wire       real_valid, real_ready, real_on;
    wire [2:0] real_key;
    wire [6:0] real_note;
    note_event u_ne (
        .clk(clk), .rst_n(rst_n), .key_state(key_state),
        .evt_ready(real_ready), .evt_valid(real_valid),
        .evt_key_id(real_key), .evt_note(real_note), .evt_on(real_on),
        .overflow_count()
    );

    // ---------------- 与 top.v 完全一致的多路器 ----------------
    wire evt_valid = bt_owner ? bt_evt_valid : real_valid;
    wire [2:0] evt_key = bt_owner ? bt_evt_key : real_key;
    wire [6:0] evt_note = bt_owner ? bt_evt_note : real_note;
    wire evt_on = bt_owner ? bt_evt_on : real_on;
    wire evt_ready;
    assign real_ready   = !bt_owner && evt_ready;
    assign bt_evt_ready =  bt_owner && evt_ready;

    // ---------------- 声部分配 ----------------
    wire [3:0]  gate, trig;
    wire [27:0] vnote;
    wire [3:0]  vbusy, edone;
    voice_alloc #(.NVOICE(4)) u_va (
        .clk(clk), .rst_n(rst_n),
        .evt_valid(evt_valid), .evt_ready(evt_ready),
        .evt_key_id(evt_key), .evt_note(evt_note), .evt_on(evt_on),
        .voice_busy(vbusy), .env_done(edone), .voice_note(vnote),
        .voice_gate(gate), .voice_trigger(trig)
    );
    assign vbusy = 4'd0;
    assign edone = 4'd0;

    // ---------------- 统计 ----------------
    integer trig_cnt = 0;
    always @(posedge clk) if (trig != 4'd0) trig_cnt = trig_cnt + 1;
    integer notes_on = 0, notes_off = 0;
    always @(posedge clk) if (evt_valid && evt_ready) begin
        if (evt_on) notes_on = notes_on + 1;
        else        notes_off = notes_off + 1;
    end

    // ---------------- CRC8（与 RTL / web/js/serial.js 同一算法）----------------
    function [7:0] crc8;
        input [7:0] c;
        input [7:0] d;
        integer i;
        reg [7:0] x;
        begin
            x = c ^ d;
            for (i = 0; i < 8; i = i + 1)
                x = x[7] ? ((x << 1) ^ 8'h07) : (x << 1);
            crc8 = x;
        end
    endfunction

    // ---------------- 发一个字节 ----------------
    task send_byte;
        input [7:0] b;
        integer k;
        begin
            uart_rx_pin = 1'b0;                 // 起始位
            #(BIT_NS);
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx_pin = b[k];             // LSB first
                #(BIT_NS);
            end
            uart_rx_pin = 1'b1;                 // 停止位
            #(BIT_NS);
        end
    endtask

    // ---------------- 发一帧音符命令 ----------------
    task send_note_frame;
        input [6:0] note;
        input       on;
        input [2:0] keyid;
        reg   [7:0] body0, body1, body2, body3, crc;
        begin
            body0 = 8'h02;                                  // 类型：音符
            body1 = 8'h02;                                  // 长度：2
            body2 = {1'b0, note};                           // 音号
            body3 = {(keyid), on};                          // bit0=按下, bit3:1=键号
            crc   = crc8(8'h00, body0);
            crc   = crc8(crc,   body1);
            crc   = crc8(crc,   body2);
            crc   = crc8(crc,   body3);
            send_byte(8'hAA); send_byte(8'h55);
            send_byte(body0); send_byte(body1);
            send_byte(body2); send_byte(body3);
            send_byte(crc);
            #2000;
        end
    endtask

    task send_release_frame;
        reg [7:0] crc;
        begin
            crc = crc8(8'h00, 8'h03);
            crc = crc8(crc,   8'h00);
            send_byte(8'hAA); send_byte(8'h55);
            send_byte(8'h03); send_byte(8'h00);
            send_byte(crc);
            #2000;
        end
    endtask

    integer i;
    integer seed = 32'h1234_5678;

    initial begin

        #1000;
        rst_n = 1'b1;
        #2000;

        // ===== 阶段 1：蓝牙音符按下 =====
        $display("\n=== [1] 蓝牙 note-on: note=60 key=0 ===");
        send_note_frame(7'd60, 1'b1, 3'd0);
        #50000;
        $display("  owner=%b  gate=%b  vnote[6:0]=%0d  (期望 owner=1 gate=0001 note=60)",
                 bt_owner, gate, vnote[6:0]);
        if (!bt_owner) $display("  ** FAIL: owner 没有置位 **");
        if (gate[0] !== 1'b1) $display("  ** FAIL: 声部 0 没有被门控 **");
        if (vnote[6:0] !== 7'd60) $display("  ** FAIL: 音号不是 60 **");

        // ===== 阶段 2：蓝牙音符松开 =====
        $display("\n=== [2] 蓝牙 note-off: note=60 key=0 ===");
        send_note_frame(7'd60, 1'b0, 3'd0);
        #50000;
        $display("  owner=%b  gate=%b  (期望 gate=0000)", bt_owner, gate);
        if (gate !== 4'd0) $display("  ** FAIL: 松键后门控没有释放 **");

        // ===== 阶段 3：交还触摸板 =====
        $display("\n=== [3] 交还触摸板 (type=03) ===");
        send_release_frame;
        #50000;
        $display("  owner=%b  (期望 0)", bt_owner);
        if (bt_owner !== 1'b0) $display("  ** FAIL: owner 没有交还 **");

        // ===== 阶段 4：触摸板按 TP0 =====
        $display("\n=== [4] 触摸板按下 TP0 ===");
        key_state = 8'b0000_0001;
        #50000;
        $display("  gate=%b  vnote[6:0]=%0d  (期望 gate=0001 note=60)", gate, vnote[6:0]);
        if (gate[0] !== 1'b1) $display("  ** FAIL: 触摸板按键没有发声部 **");

        // ===== 阶段 5：松开 =====
        $display("\n=== [5] 触摸板松开 TP0 ===");
        key_state = 8'b0000_0000;
        #50000;
        $display("  gate=%b  (期望 0000)", gate);
        if (gate !== 4'd0) $display("  ** FAIL: 触摸板松键后门控没有释放 **");

        // ===== 阶段 6：5 个键同时按（限键 4 的语义）=====
        $display("\n=== [6] 同时按 5 个键（键限 4）===");
        key_state = 8'b0001_1111;
        #200000;
        $display("  notes_on=%0d  gate=%b", notes_on, gate);
        key_state = 8'd0;
        #200000;
        $display("  notes_off=%0d  gate=%b (松键后应为 0000)", notes_off, gate);
        if (gate !== 4'd0) $display("  ** FAIL: 5 键场景后仍有门控残留 **");

        // ===== 阶段 7：随机噪声字节流的误触发率 =====
        $display("\n=== [7] 随机字节流（模拟 RX 线上的干扰）===");
        trig_cnt = 0;
        for (i = 0; i < 1000; i = i + 1) begin
            send_byte($random(seed) & 8'hFF);
        end
        #100000;
        $display("  1000 个随机字节 -> 误发音符 %0d 个, owner=%b", trig_cnt, bt_owner);
        $display("  换算：每 %0d 个字节一次误触发", (trig_cnt == 0) ? 0 : 1000 / trig_cnt);

        $display("\n=== 仿真结束 ===");
        $finish;
    end

    initial begin
        #600_000_000;
        $display("*** TIMEOUT ***");
        $finish;
    end
endmodule
`default_nettype wire
