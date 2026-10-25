// tb_voice_alloc.v -- self-checking testbench
// 用一个简化的"占用模型"代替真实 adsr：gate 拉高即忙，
// gate 拉低后忙 3 拍再给一个 env_done 脉冲。
// 这样能单独验证分配逻辑，不被包络时序干扰。
`timescale 1ns / 1ps
`default_nettype none
module tb_voice_alloc;

    localparam NVOICE = 4;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg        evt_valid = 1'b0;
    reg [2:0]  evt_key_id = 3'd0;
    reg [6:0]  evt_note = 7'd60;
    reg        evt_on = 1'b0;

    wire                  evt_ready;
    wire [NVOICE*7-1:0]   voice_note;
    wire [NVOICE-1:0]     voice_gate;
    wire [NVOICE-1:0]     voice_trigger;

    reg  [NVOICE-1:0]     voice_busy = 0;
    reg  [NVOICE-1:0]     env_done = 0;

    integer errors = 0;
    integer k;
    integer k1;
    integer trig_cnt [0:NVOICE-1];

    always #5 clk = ~clk;

    voice_alloc #(.NVOICE(NVOICE)) dut (
        .clk(clk), .rst_n(rst_n),
        .evt_valid(evt_valid), .evt_ready(evt_ready),
        .evt_key_id(evt_key_id), .evt_note(evt_note), .evt_on(evt_on),
        .voice_busy(voice_busy), .env_done(env_done),
        .voice_note(voice_note), .voice_gate(voice_gate), .voice_trigger(voice_trigger)
    );

    // ---- 简化占用模型（代替 adsr）----
    reg [3:0] relcnt [0:NVOICE-1];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            voice_busy <= 4'b0;
            env_done   <= 4'b0;
            for (k = 0; k < NVOICE; k = k + 1) relcnt[k] <= 4'd0;
        end else begin
            env_done <= 4'b0;
            for (k = 0; k < NVOICE; k = k + 1) begin
                if (voice_gate[k]) begin
                    voice_busy[k] <= 1'b1;
                    relcnt[k]     <= 4'd0;
                end else if (voice_busy[k]) begin
                    if (relcnt[k] >= 4'd2) begin
                        voice_busy[k] <= 1'b0;
                        env_done[k]   <= 1'b1;
                    end else begin
                        relcnt[k] <= relcnt[k] + 4'd1;
                    end
                end
            end
        end
    end

    // trigger 脉冲计数，用来确认"重按确实重新起音了"
    always @(posedge clk) begin
        for (k1 = 0; k1 < NVOICE; k1 = k1 + 1)
            if (voice_trigger[k1]) trig_cnt[k1] = trig_cnt[k1] + 1;
    end

    // ---- 工具函数 ----
    function integer ngate;
        input dummy;
        integer t;
        begin
            ngate = 0;
            for (t = 0; t < NVOICE; t = t + 1)
                if (voice_gate[t]) ngate = ngate + 1;
        end
    endfunction

    function has_note;
        input [6:0] n;
        integer t;
        begin
            has_note = 1'b0;
            for (t = 0; t < NVOICE; t = t + 1)
                if (voice_gate[t] && (voice_note[t*7 +: 7] == n)) has_note = 1'b1;
        end
    endfunction

    task dump;
        integer t;
        begin
            $write("    voices:");
            for (t = 0; t < NVOICE; t = t + 1)
                $write(" [%0d]note=%0d key=%0d gate=%b busy=%b",
                       t, voice_note[t*7 +: 7], dut.v_key[t], voice_gate[t], voice_busy[t]);
            $write("\n");
        end
    endtask

    task press;
        input [2:0] key;
        input [6:0] note;
        begin
            @(negedge clk);
            evt_valid = 1'b1; evt_key_id = key; evt_note = note; evt_on = 1'b1;
            @(negedge clk);
            evt_valid = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    // 注意：不能叫 release —— 那是 Verilog 保留字（force/release）
    task release_key;
        input [2:0] key;
        begin
            @(negedge clk);
            evt_valid = 1'b1; evt_key_id = key; evt_note = 7'd0; evt_on = 1'b0;
            @(negedge clk);
            evt_valid = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task expect_gates;
        input integer exp_n;
        input [511:0] name;
        begin
            if (ngate(1'b0) !== exp_n) begin
                $display("  FAIL  %0s : %0d gates active, expect %0d", name, ngate(1'b0), exp_n);
                errors = errors + 1;
            end else begin
                $display("  ok    %0s : %0d gates active", name, ngate(1'b0));
            end
        end
    endtask

    task expect_note;
        input [6:0] n;
        input exp;
        input [511:0] name;
        begin
            if (has_note(n) !== exp) begin
                $display("  FAIL  %0s : note %0d present=%b, expect %b", name, n, has_note(n), exp);
                errors = errors + 1;
            end else begin
                $display("  ok    %0s : note %0d present=%b", name, n, has_note(n));
            end
        end
    endtask

    initial begin
        for (k = 0; k < NVOICE; k = k + 1) trig_cnt[k] = 0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        $display("=== voice_alloc self-check ===");
        $display("  evt_ready=%b (should be 1)", evt_ready);
        expect_gates(0, "after reset, all idle");

        // ---- 1) 基本分配 ----
        $display("  -- press key0 (C4=60) --");
        press(3'd0, 7'd60);
        expect_gates(1, "key0 pressed");
        expect_note(7'd60, 1'b1, "note 60 sounding");

        // ---- 2) 同一个键再按一次，不能占两路 ----
        $display("  -- press key0 again --");
        press(3'd0, 7'd60);
        expect_gates(1, "same key pressed twice");
        if (trig_cnt[0] < 2) begin
            $display("  FAIL  retrigger did not pulse (trig_cnt[0]=%0d)", trig_cnt[0]);
            errors = errors + 1;
        end else begin
            $display("  ok    retrigger pulsed again (trig_cnt[0]=%0d)", trig_cnt[0]);
        end
        dump;

        // ---- 3) 填满 4 路 ----
        press(3'd1, 7'd62); expect_gates(2, "key1 pressed");
        press(3'd2, 7'd64); expect_gates(3, "key2 pressed");
        press(3'd3, 7'd65); expect_gates(4, "key3 pressed");
        dump;

        // ---- 4) 满员：第 5 个键应偷最老的（note 60）----
        $display("  -- press key4 (G4=67) with all 4 busy --");
        press(3'd4, 7'd67);
        expect_gates(4, "5th key steals");
        expect_note(7'd67, 1'b1, "new note 67 sounding");
        expect_note(7'd60, 1'b0, "oldest note 60 was stolen");
        dump;

        // ---- 5) 被偷走的键松键，不能影响别人 ----
        $display("  -- release key0 (already stolen) --");
        release_key(3'd0);
        expect_gates(4, "release of stolen key ignored");
        expect_note(7'd67, 1'b1, "stolen voice still sounding");
        dump;

        // ---- 6) 正常松键 ----
        $display("  -- release key2 (note 64) --");
        release_key(3'd2);
        expect_gates(3, "key2 released");
        expect_note(7'd64, 1'b0, "note 64 released");
        dump;

        // ---- 7) 等释放尾音放完，再按键应复用空闲路（不偷）----
        $display("  -- wait env_done, then press key5 (A4=69) --");
        repeat (8) @(posedge clk);
        press(3'd5, 7'd69);
        expect_gates(4, "key5 reuses freed voice");
        expect_note(7'd69, 1'b1, "note 69 sounding");
        expect_note(7'd62, 1'b1, "note 62 untouched");
        expect_note(7'd65, 1'b1, "note 65 untouched");
        expect_note(7'd67, 1'b1, "note 67 untouched");
        dump;

        // ---- 8) 同一个键连按多次，仍然只占一路 ----
        $display("  -- press key5 three times --");
        press(3'd5, 7'd69);
        press(3'd5, 7'd69);
        press(3'd5, 7'd69);
        expect_gates(4, "repeated presses do not leak voices");
        dump;

        // ---- 9) 全部松开 ----
        $display("  -- release all --");
        release_key(3'd1); release_key(3'd3); release_key(3'd4); release_key(3'd5);
        expect_gates(0, "all released");

        // ---- 10) 释放完成后能重新分配满 4 路 ----
        $display("  -- press 4 new keys --");
        repeat (8) @(posedge clk);
        press(3'd0, 7'd60);
        press(3'd1, 7'd62);
        press(3'd2, 7'd64);
        press(3'd3, 7'd65);
        expect_gates(4, "4 voices reallocated after release");
        expect_note(7'd60, 1'b1, "note 60 back");
        dump;

        $display("=== %0s (%0d errors) ===", (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

endmodule
`default_nettype wire
