// tb_adsr.v -- self-checking testbench
// 验证：起音能爬到满幅、衰减停在 sustain、松键真的降到 0 才清 busy、
//       并输出 env_done 脉冲。
`timescale 1ns / 1ps
`default_nettype none
module tb_adsr;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg wave_valid = 1'b0;
    reg signed [15:0] wave = 16'sd16384;   // 恒定输入，方便从输出反推包络电平
    reg gate = 1'b0;
    reg trigger = 1'b0;

    wire signed [15:0] sample;
    wire valid, busy, env_done;

    integer errors = 0;
    integer nsamp = 0;
    integer clk_cnt = 0;
    reg [2:0] state_d = 3'd0;
    reg seen_done = 1'b0;
    integer peak = -1;
    integer sus_seen = -1;

    always #5 clk = ~clk;

    adsr #(.FS_HZ(46875)) dut (
        .clk(clk), .rst_n(rst_n),
        .wave_valid(wave_valid), .wave(wave),
        .gate(gate), .trigger(trigger),
        .sample(sample), .valid(valid), .busy(busy), .env_done(env_done)
    );

    // 每 4 个时钟产生一个样本使能（真实系统里是 576，这里缩小以便快速仿真）
    always @(posedge clk) begin
        clk_cnt <= clk_cnt + 1;
        wave_valid <= ((clk_cnt % 4) == 0);
    end

    // 采样计数 + 状态迁移日志
    always @(posedge clk) begin
        if (wave_valid) nsamp = nsamp + 1;
        if (env_done) seen_done = 1'b1;
        if (dut.level > peak) peak = dut.level;
        if (dut.state !== state_d) begin
            $display("    [sample %5d] state %0d -> %0d  level=%0d  busy=%b",
                     nsamp, state_d, dut.state, dut.level, busy);
            state_d = dut.state;
        end
        if (dut.state == 3'd3 && sus_seen < 0) begin
            sus_seen = dut.level;
            $display("    [sample %5d] enter SUSTAIN, level=%0d", nsamp, dut.level);
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("=== adsr self-check ===");
        $display("  after reset: sample=%0d busy=%b valid=%b", sample, busy, valid);
        if (sample !== 16'sd0 || busy !== 1'b0) begin
            $display("  FAIL  reset state wrong");
            errors = errors + 1;
        end

        // ---- 按下：gate 拉高 + trigger 单拍脉冲 ----
        $display("  -- press key --");
        gate = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk); trigger = 1'b1;
        @(negedge clk); trigger = 1'b0;

        // 等起音结束
        wait (dut.state == 3'd2);
        $display("  attack done at sample %0d (expect ~462)", nsamp);
        if (dut.level !== 16'sd32767) begin
            $display("  FAIL  peak level=%0d, expect 32767", dut.level);
            errors = errors + 1;
        end else begin
            $display("  ok    peak level = 32767");
        end

        // 等衰减结束
        wait (dut.state == 3'd3);
        repeat (3) @(posedge clk);
        if (dut.level !== 16'sd19660) begin
            $display("  FAIL  sustain level=%0d, expect 19660", dut.level);
            errors = errors + 1;
        end else begin
            $display("  ok    sustain level = 19660");
        end
        // 输出应约为 16384 * 19660 / 32768 = 9830
        if (sample < 16'sd9820 || sample > 16'sd9840) begin
            $display("  FAIL  sustained sample=%0d, expect ~9830", sample);
            errors = errors + 1;
        end else begin
            $display("  ok    sustained sample = %0d (~9830)", sample);
        end

        // ---- 保持期间的音量应稳定 ----
        repeat (20) @(posedge clk);
        if (sample !== 16'sd9830) begin
            $display("  FAIL  sustain not steady: %0d", sample);
            errors = errors + 1;
        end else begin
            $display("  ok    sustain steady at %0d", sample);
        end

        // ---- 保持中重触发：应回到起音 ----
        $display("  -- retrigger while holding --");
        @(negedge clk); trigger = 1'b1;
        @(negedge clk); trigger = 1'b0;
        repeat (4) @(posedge clk);
        if (dut.state !== 3'd1) begin
            $display("  FAIL  retrigger did not restart attack (state=%0d)", dut.state);
            errors = errors + 1;
        end else begin
            $display("  ok    retrigger restarted attack");
        end
        wait (dut.state == 3'd3);

        // ---- 松键：必须降到 0 才清 busy ----
        $display("  -- release key --");
        @(negedge clk); gate = 1'b0;
        wait (dut.state == 3'd4);
        $display("    enter RELEASE at sample %0d", nsamp);
        wait (busy == 1'b0);
        repeat (3) @(posedge clk);

        if (dut.level !== 16'sd0) begin
            $display("  FAIL  level=%0d after release, expect 0", dut.level);
            errors = errors + 1;
        end else begin
            $display("  ok    level reached exactly 0");
        end
        if (sample !== 16'sd0) begin
            $display("  FAIL  sample=%0d after release, expect 0", sample);
            errors = errors + 1;
        end else begin
            $display("  ok    sample = 0 (no stuck note)");
        end
        if (!seen_done) begin
            $display("  FAIL  env_done pulse never asserted");
            errors = errors + 1;
        end else begin
            $display("  ok    env_done pulse seen");
        end

        // ---- 松键后再按键，应能重新发声 ----
        $display("  -- press again --");
        gate = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk); trigger = 1'b1;
        @(negedge clk); trigger = 1'b0;
        repeat (40) @(posedge clk);
        if (sample <= 16'sd0) begin
            $display("  FAIL  voice did not sound again: sample=%0d", sample);
            errors = errors + 1;
        end else begin
            $display("  ok    voice sounds again, sample=%0d", sample);
        end

        $display("=== %0s (%0d errors) ===", (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

endmodule
`default_nettype wire
