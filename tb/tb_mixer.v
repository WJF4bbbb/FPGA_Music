// tb_mixer.v -- self-checking testbench（已按 interfaces.md V1.1 更新）
//
// 这一版 mixer 的行为变了，测试期望值也跟着变：
//   旧：sum * gain >> 16        —— 4 路满幅必然削顶
//   新：sum >> 2 * gain >> 16   —— 先留出 4 路余量，正常演奏不该削顶
//
// 所以本 tb 验证三件事：
//   ① 定标正确（含 >>2 的余量）
//   ② 4 路满幅**不回绕**：输出仍是接近 +32767 的大正数，不会突然翻成负数
//   ③ 有了余量后 clip_count 应恒为 0（饱和逻辑退化成安全网）
//
// 时序约定：在下降沿改输入，在上升沿后 1ns 采样 DUT 输出，
// 采完立刻撤掉 voice_valid（模拟真实的一拍脉冲），避免重复计数。
// frame_tick 在每次装载新增益时先打一拍，让 mixer 锁存。
`timescale 1ns / 1ps
`default_nettype none
module tb_mixer;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ft = 1'b0;                 // frame_tick
    reg [4*16-1:0] vs;
    reg [3:0]      vv;
    reg [15:0]     gain;
    wire signed [15:0] sample;
    wire           valid;
    wire [31:0]    clip_count;

    integer errors = 0;

    always #5 clk = ~clk;

    mixer #(.NVOICE(4)) dut (
        .clk(clk), .rst_n(rst_n), .frame_tick(ft),
        .voice_samples(vs), .voice_valid(vv), .master_gain(gain),
        .sample(sample), .valid(valid), .clip_count(clip_count)
    );

    // 在下降沿装载一路测试向量：先打一拍 frame_tick 锁存增益，再给 voice_valid
    task apply;
        input signed [15:0] a, b, c, d;
        input [3:0]         v;
        input [15:0]        g;
        begin
            @(negedge clk);
            vs   = {d, c, b, a};
            gain = g;
            ft   = 1'b1;              // 锁存新增益
            @(negedge clk);
            ft   = 1'b0;
            vv   = v;                 // 下一拍进数据
        end
    endtask

    task expect_s;
        input signed [15:0] exp;
        input [511:0]       name;
        begin
            @(posedge clk); #1;
            vv = 4'b0000;                 // 单拍脉冲
            if (sample !== exp) begin
                $display("  FAIL  %0s : got %0d, expect %0d", name, sample, exp);
                errors = errors + 1;
            end else begin
                $display("  ok    %0s : %0d", name, sample);
            end
        end
    endtask

    task expect_v;
        input exp_v;
        input [511:0] name;
        begin
            @(posedge clk); #1;
            vv = 4'b0000;
            if (valid !== exp_v) begin
                $display("  FAIL  %0s : valid=%b, expect %b", name, valid, exp_v);
                errors = errors + 1;
            end else begin
                $display("  ok    %0s : valid=%b", name, valid);
            end
        end
    endtask

    initial begin
        vs = 64'd0; vv = 4'b0000; gain = 16'd65535; ft = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        #1;

        $display("=== mixer self-check (V1.1: sum>>2 headroom) ===");
        $display("  after reset: sample=%0d valid=%b", sample, valid);

        // --- 定标：单路 10000，>>2 之后是 2500 ---
        apply(16'sd10000, 16'sd0, 16'sd0, 16'sd0, 4'b0001, 16'd65535);
        expect_s(16'sd2499, "1 lane 10000, gain=65535 (2500*65535>>16)");

        apply(16'sd10000, 16'sd0, 16'sd0, 16'sd0, 4'b0001, 16'd32768);
        expect_s(16'sd1250, "1 lane 10000, gain=32768 (half)");

        apply(16'sd30000, 16'sd0, 16'sd0, 16'sd0, 4'b0001, 16'd0);
        expect_s(16'sd0, "gain=0 -> silence");

        // --- 4 路满幅：有余量，所以不该削顶，更不该回绕 ---
        // 131068 >> 2 = 32767；32767*65535>>16 = 32766
        apply(16'sd32767, 16'sd32767, 16'sd32767, 16'sd32767, 4'b1111, 16'd65535);
        expect_s(16'sd32766, "4x +32767 -> 32766 (no wrap, no clip)");

        // -131072 >> 2 = -32768；-32768*65535>>16 = -32768
        apply(-16'sd32768, -16'sd32768, -16'sd32768, -16'sd32768, 4'b1111, 16'd65535);
        expect_s(-16'sd32768, "4x -32768 -> -32768 (no wrap)");

        // --- 正负抵消：acc=-1，>>2 仍是 -1 ---
        apply(16'sd32767, -16'sd32768, 16'sd0, 16'sd0, 4'b1111, 16'd65535);
        expect_s(-16'sd1, "+32767 and -32768 -> -1");

        // --- 无效声部不参与累加 ---
        apply(16'sd10000, 16'sd10000, 16'sd10000, 16'sd10000, 4'b0001, 16'd65535);
        expect_s(16'sd2499, "only lane0 valid");

        // --- 全无效：valid 应拉低，sample 保持上一帧 ---
        apply(16'sd10000, 16'sd0, 16'sd0, 16'sd0, 4'b0000, 16'd65535);
        expect_v(1'b0, "no valid lane -> valid=0");
        if (sample !== 16'sd2499) begin
            $display("  FAIL  sample should hold 2499, got %0d", sample);
            errors = errors + 1;
        end else begin
            $display("  ok    sample holds previous frame: %0d", sample);
        end

        // --- 有余量后不该再有削顶；饱和只是安全网 ---
        if (clip_count !== 32'd0) begin
            $display("  FAIL  clip_count=%0d, expect 0 (headroom should prevent clipping)", clip_count);
            errors = errors + 1;
        end else begin
            $display("  ok    clip_count = 0 (headroom works)");
        end

        $display("=== %0s (%0d errors) ===", (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

endmodule
`default_nettype wire
