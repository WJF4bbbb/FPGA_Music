// tb_mixer.v -- self-checking testbench
// 重点验证：4 路满幅相加时是"饱和"而不是"回绕"。
// 回绕的表现是：+32767 附近突然变成大负数 —— 听感上是撕裂爆音。
//
// 时序约定：在下降沿改输入，在上升沿后 1ns 采样 DUT 输出，
// 采完立刻撤掉 voice_valid（模拟真实的一拍脉冲），避免重复计数。
`timescale 1ns / 1ps
`default_nettype none
module tb_mixer;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [4*16-1:0] vs;
    reg [3:0]      vv;
    reg [15:0]     gain;
    wire signed [15:0] sample;
    wire           valid;
    wire [31:0]    clip_count;

    integer errors = 0;

    always #5 clk = ~clk;

    mixer #(.NVOICE(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .voice_samples(vs), .voice_valid(vv), .master_gain(gain),
        .sample(sample), .valid(valid), .clip_count(clip_count)
    );

    // 在下降沿装载一路测试向量
    task apply;
        input signed [15:0] a, b, c, d;
        input [3:0]         v;
        input [15:0]        g;
        begin
            @(negedge clk);
            vs   = {d, c, b, a};
            vv   = v;
            gain = g;
        end
    endtask

    task expect_s;
        input signed [15:0] exp;
        input [255:0]       name;
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
        vs = 64'd0; vv = 4'b0000; gain = 16'd65535;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        #1;

        $display("=== mixer self-check ===");
        $display("  after reset: sample=%0d valid=%b", sample, valid);

        // --- 单路，验证定标正确 ---
        apply(16'sd10000, 16'sd0, 16'sd0, 16'sd0, 4'b0001, 16'd65535);
        expect_s(16'sd9999, "1 lane 10000, gain=65535 (~1.0)");

        apply(16'sd10000, 16'sd0, 16'sd0, 16'sd0, 4'b0001, 16'd32768);
        expect_s(16'sd5000, "1 lane 10000, gain=32768 (0.5)");

        apply(16'sd30000, 16'sd0, 16'sd0, 16'sd0, 4'b0001, 16'd0);
        expect_s(16'sd0, "gain=0 -> silence");

        // --- 4 路满幅：必须饱和，不能回绕 ---
        apply(16'sd32767, 16'sd32767, 16'sd32767, 16'sd32767, 4'b1111, 16'd65535);
        expect_s(16'sd32767, "4x +32767 saturates at +32767");

        apply(-16'sd32768, -16'sd32768, -16'sd32768, -16'sd32768, 4'b1111, 16'd65535);
        expect_s(-16'sd32768, "4x -32768 saturates at -32768");

        // --- 刚好到上限，不该被误判成溢出 ---
        apply(16'sd16384, 16'sd16384, 16'sd0, 16'sd0, 4'b1111, 16'd65535);
        expect_s(16'sd32767, "2x 16384 -> exactly +32767");

        // --- 正负抵消 ---
        apply(16'sd32767, -16'sd32768, 16'sd0, 16'sd0, 4'b1111, 16'd65535);
        expect_s(-16'sd1, "+32767 and -32768 -> -1");

        // --- 无效声部不参与累加 ---
        apply(16'sd10000, 16'sd10000, 16'sd10000, 16'sd10000, 4'b0001, 16'd65535);
        expect_s(16'sd9999, "only lane0 valid");

        // --- 全无效：valid 应拉低，sample 保持上一帧 ---
        apply(16'sd10000, 16'sd0, 16'sd0, 16'sd0, 4'b0000, 16'd65535);
        expect_v(1'b0, "no valid lane -> valid=0");
        if (sample !== 16'sd9999) begin
            $display("  FAIL  sample should hold 9999, got %0d", sample);
            errors = errors + 1;
        end else begin
            $display("  ok    sample holds previous frame: %0d", sample);
        end

        // --- 饱和计数器：只应记录上面 2 次溢出 ---
        if (clip_count !== 32'd2) begin
            $display("  FAIL  clip_count=%0d, expect 2", clip_count);
            errors = errors + 1;
        end else begin
            $display("  ok    clip_count = %0d", clip_count);
        end

        $display("=== %0s (%0d errors) ===", (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

endmodule
`default_nettype wire
