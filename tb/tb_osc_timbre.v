// tb_osc_timbre.v -- self-checking testbench
// 验证 osc 的两个"维度"：
//   1) 四种音色都发得出来，而且基频一致（只是波形不同）
//   2) bend ±2 半音能把频率改对，而且改的时候相位连续（不产生咔声）
//
// 频率用"数上升过零点"测：跑一段样本，量相邻两次过零之间的平均样本数，
// 也就是周期。周期 * (1/FS) = 一个声音周期的时间。
`timescale 1ns / 1ps
`default_nettype none
module tb_osc_timbre;

    localparam real FS = 46875.0;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg        frame_tick = 1'b1;      // 每个时钟出一个样本，测周期用样本数就够了
    reg [6:0]  note = 7'd60;
    reg signed [3:0] bend = 4'sd0;
    reg [1:0]  timbre = 2'd0;

    wire signed [15:0] wave;
    wire valid;

    integer errors = 0;

    // 统计量
    integer nsamp = 0;
    integer ncross = 0;
    integer first_cross = 0;
    integer last_cross = 0;
    integer wmin = 0;
    integer wmax = 0;
    integer njump = 0;          // 相邻样本跳变 > 20000 的次数
    integer maxdelta = 0;
    integer seen_first = 0;
    reg signed [15:0] prev = 16'sd0;

    real    meas_period, meas_freq, exp_period;
    integer d;

    always #5 clk = ~clk;

    osc #(.FS_HZ(46875)) dut (
        .clk(clk), .rst_n(rst_n), .frame_tick(frame_tick),
        .note(note), .bend(bend), .timbre(timbre),
        .wave(wave), .valid(valid)
    );

    // 统计每个样本
    always @(posedge clk) begin
        if (rst_n && valid) begin
            nsamp = nsamp + 1;
            if (!seen_first) begin
                wmin = wave; wmax = wave;
                prev = wave;
                seen_first = 1;
            end else begin
                if (wave < wmin) wmin = wave;
                if (wave > wmax) wmax = wave;
                d = wave - prev;
                if (d < 0) d = -d;
                if (d > maxdelta) maxdelta = d;
                if (d > 20000) njump = njump + 1;
                if (prev < 0 && wave >= 0) begin
                    if (ncross == 0) first_cross = nsamp;
                    last_cross = nsamp;
                    ncross = ncross + 1;
                end
                prev = wave;
            end
        end
    end

    task clear_stats;
        begin
            nsamp = 0; ncross = 0; first_cross = 0; last_cross = 0;
            njump = 0; maxdelta = 0; seen_first = 0; prev = 16'sd0;
            wmin = 0; wmax = 0;
        end
    endtask

    task run_n;
        input integer n;
        integer c;
        begin
            for (c = 0; c < n; c = c + 1) @(posedge clk);
        end
    endtask

    // 检查测出来的周期与理论值的偏差
    task check_period;
        input real        exp_samples;
        input [511:0]     name;
        begin
            if (ncross < 3) begin
                $display("  FAIL  %0s : only %0d zero crossings, no signal?", name, ncross);
                errors = errors + 1;
            end else begin
                meas_period = 1.0 * (last_cross - first_cross) / (ncross - 1);
                meas_freq   = FS / meas_period;
                if (meas_period > exp_samples * 1.02 || meas_period < exp_samples * 0.98) begin
                    $display("  FAIL  %0s : period=%0.2f samples (%0.1f Hz), expect %0.2f (%0.1f Hz)",
                             name, meas_period, meas_freq, exp_samples, FS/exp_samples);
                    errors = errors + 1;
                end else begin
                    $display("  ok    %0s : period=%0.2f samples -> %0.1f Hz",
                             name, meas_period, meas_freq);
                end
            end
        end
    endtask

    initial begin
        // C4 (note 60) 的 FCW = 23971696 -> 理论周期 = 2^32 / FCW
        exp_period = 4294967296.0 / 23971696.0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("=== osc timbre / bend self-check ===");
        $display("  C4 expected period = %0.3f samples (%0.1f Hz)", exp_period, FS/exp_period);

        // ---------- 四种音色，基频应完全一致 ----------
        $display("  -- timbre 0: sine --");
        timbre = 2'd0; clear_stats; run_n(3000);
        check_period(exp_period, "sine C4");
        $display("       range [%0d, %0d], max step %0d, big jumps %0d",
                 wmin, wmax, maxdelta, njump);
        if (wmin > -30000 || wmax < 30000) begin
            $display("  FAIL  sine amplitude too small");
            errors = errors + 1;
        end
        if (njump != 0) begin
            $display("  FAIL  sine should be smooth, got %0d jumps", njump);
            errors = errors + 1;
        end

        $display("  -- timbre 1: square --");
        timbre = 2'd1; clear_stats; run_n(3000);
        check_period(exp_period, "square C4");
        $display("       range [%0d, %0d], max step %0d, big jumps %0d",
                 wmin, wmax, maxdelta, njump);
        if (wmin != -32768 || wmax != 32767) begin
            $display("  FAIL  square must swing full scale, got [%0d, %0d]", wmin, wmax);
            errors = errors + 1;
        end
        // 方波每周期应恰好两次跳变（上沿一次、下沿一次）
        if (njump < 2*(ncross-1) - 2 || njump > 2*(ncross-1) + 2) begin
            $display("  FAIL  square jumps=%0d, expect ~%0d (2 per period)", njump, 2*(ncross-1));
            errors = errors + 1;
        end else begin
            $display("  ok    square has 2 transitions per period (%0d jumps / %0d periods)",
                     njump, ncross-1);
        end

        $display("  -- timbre 2: saw --");
        timbre = 2'd2; clear_stats; run_n(3000);
        check_period(exp_period, "saw C4");
        $display("       range [%0d, %0d], max step %0d, big jumps %0d",
                 wmin, wmax, maxdelta, njump);
        if (njump < (ncross-1) - 2 || njump > (ncross-1) + 2) begin
            $display("  FAIL  saw jumps=%0d, expect ~%0d (1 per period)", njump, ncross-1);
            errors = errors + 1;
        end else begin
            $display("  ok    saw has 1 wrap per period (%0d jumps / %0d periods)",
                     njump, ncross-1);
        end

        $display("  -- timbre 3: triangle --");
        timbre = 2'd3; clear_stats; run_n(3000);
        check_period(exp_period, "triangle C4");
        $display("       range [%0d, %0d], max step %0d, big jumps %0d",
                 wmin, wmax, maxdelta, njump);
        if (njump != 0) begin
            $display("  FAIL  triangle should be continuous, got %0d jumps", njump);
            errors = errors + 1;
        end

        // ---------- bend 变调 ----------
        timbre = 2'd0;
        $display("  -- bend +2 semitones --");
        bend = 4'sd2; clear_stats; run_n(3000);
        check_period(exp_period / 1.122462, "sine C4 bend +2");

        $display("  -- bend -2 semitones --");
        bend = -4'sd2; clear_stats; run_n(3000);
        check_period(exp_period / 0.890899, "sine C4 bend -2");

        $display("  -- bend +1 semitone --");
        bend = 4'sd1; clear_stats; run_n(3000);
        check_period(exp_period / 1.059463, "sine C4 bend +1");

        // ---------- 变调过程中相位必须连续（不产生咔声）----------
        $display("  -- switch bend live, phase must stay continuous --");
        bend = 4'sd0; clear_stats; run_n(600);
        bend = 4'sd2;                 // 演奏中途变调
        clear_stats; run_n(600);
        $display("       max step after bend change = %0d", maxdelta);
        if (maxdelta > 4000) begin
            $display("  FAIL  phase jump on bend change (max step %0d)", maxdelta);
            errors = errors + 1;
        end else begin
            $display("  ok    no phase discontinuity on bend change");
        end

        // ---------- 换音色时相位也不能被清掉 ----------
        $display("  -- switch timbre live --");
        bend = 4'sd0; timbre = 2'd0; run_n(200);
        timbre = 2'd1;                // 切到方波
        clear_stats; run_n(200);
        $display("       max step after timbre change = %0d (square jumps are expected)", maxdelta);
        if (ncross < 1) begin
            $display("  FAIL  no oscillation after timbre switch");
            errors = errors + 1;
        end else begin
            $display("  ok    still oscillating after timbre switch (%0d crossings)", ncross);
        end

        $display("=== %0s (%0d errors) ===", (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

endmodule
`default_nettype wire
