// tb_chain.v -- B 侧整链仿真
// 把 top.v 里属于 B 的那半边原样串起来：
//     voice_alloc -> (osc + adsr) x 4 -> mixer
// 验证：弹和弦能出声、偷声部不出错、松手真的静音、混音不溢出。
//
// 注意：这里自己产生 frame_tick（真实系统由 audio_timing 提供），
// 并且不去碰 I2S 那一段。整机联调由 A 的 top.v 负责。
`timescale 1ns / 1ps
`default_nettype none
module tb_chain;

    localparam NVOICE = 4;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg frame_tick = 1'b0;

    // ---- 事件输入（模拟 note_event 的输出）----
    reg        evt_valid = 1'b0;
    reg [2:0]  evt_key_id = 3'd0;
    reg [6:0]  evt_note = 7'd60;
    reg        evt_on = 1'b0;
    wire       evt_ready;

    // ---- voice_alloc 输出 ----
    wire [NVOICE*7-1:0] voice_note;
    wire [NVOICE-1:0]   voice_gate;
    wire [NVOICE-1:0]   voice_trigger;

    // ---- adsr 输出 ----
    wire [NVOICE*16-1:0] voice_samples;
    wire [NVOICE-1:0]    voice_valid;
    wire [NVOICE-1:0]    voice_busy;
    wire [NVOICE-1:0]    env_done;

    // ---- mixer 输出 ----
    // 默认 1.0。注意 mixer 内部已经先 >>2 留出 4 路余量，
    // 所以这里给满增益也不会削顶（这正是 V1.1 合同的要求）。
    reg  [15:0]        master_gain = 16'd65535;
    wire signed [15:0] mixed_sample;
    wire               mixed_valid;
    wire [31:0]        clip_count;

    reg [1:0] timbre = 2'd0;
    reg signed [3:0] bend = 4'sd0;

    integer errors = 0;
    integer se_cnt = 0;

    // 窗口统计
    integer w_n = 0, w_x = 0, w_min = 0, w_max = 0;

    always #5 clk = ~clk;

    // 每 4 个时钟一个帧节拍（真实系统是 576，这里缩小以便快速仿真）
    always @(posedge clk) begin
        se_cnt     <= se_cnt + 1;
        frame_tick <= ((se_cnt % 4) == 0);
    end

    // ---------------- DUT ----------------
    voice_alloc #(.NVOICE(NVOICE)) u_voice_alloc (
        .clk(clk), .rst_n(rst_n),
        .evt_valid(evt_valid), .evt_ready(evt_ready),
        .evt_key_id(evt_key_id), .evt_note(evt_note), .evt_on(evt_on),
        .voice_busy(voice_busy), .env_done(env_done),
        .voice_note(voice_note), .voice_gate(voice_gate), .voice_trigger(voice_trigger)
    );

    genvar i;
    generate
        for (i = 0; i < NVOICE; i = i + 1) begin : voices
            wire signed [15:0] wave;
            wire               wave_valid;

            osc #(.FS_HZ(46875)) u_osc (
                .clk(clk), .rst_n(rst_n), .frame_tick(frame_tick),
                .note(voice_note[i*7 +: 7]), .bend(bend), .timbre(timbre),
                .wave(wave), .valid(wave_valid)
            );
            adsr #(.FS_HZ(46875)) u_adsr (
                .clk(clk), .rst_n(rst_n), .frame_tick(frame_tick),
                .wave_valid(wave_valid), .wave(wave),
                .gate(voice_gate[i]), .trigger(voice_trigger[i]),
                .sample(voice_samples[i*16 +: 16]), .valid(voice_valid[i]),
                .busy(voice_busy[i]), .env_done(env_done[i])
            );
        end
    endgenerate

    mixer #(.NVOICE(NVOICE)) u_mixer (
        .clk(clk), .rst_n(rst_n), .frame_tick(frame_tick),
        .voice_samples(voice_samples), .voice_valid(voice_valid),
        .master_gain(master_gain),
        .sample(mixed_sample), .valid(mixed_valid), .clip_count(clip_count)
    );

    // ---------------- 窗口统计 ----------------
    always @(posedge clk) begin
        if (rst_n && mixed_valid) begin
            w_n = w_n + 1;
            if (^mixed_sample === 1'bx) w_x = w_x + 1;
            if (mixed_sample < w_min) w_min = mixed_sample;
            if (mixed_sample > w_max) w_max = mixed_sample;
        end
    end

    task clear_win;
        begin
            w_n = 0; w_x = 0; w_min = 0; w_max = 0;
        end
    endtask

    task run_n;
        input integer n;
        integer c;
        begin
            for (c = 0; c < n; c = c + 1) @(posedge clk);
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

    task show_win;
        input [511:0] name;
        begin
            $display("  %0s : frames=%0d  range=[%0d, %0d]  x_count=%0d  clips=%0d",
                     name, w_n, w_min, w_max, w_x, clip_count);
        end
    endtask

    initial begin
        $dumpfile("sim/chain.vcd");
        $dumpvars(1, tb_chain);

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        $display("=== B-side chain self-check (voice_alloc -> osc x4 -> adsr x4 -> mixer) ===");
        $display("  evt_ready=%b  mixed_sample=%0d  mixed_valid=%b", evt_ready, mixed_sample, mixed_valid);

        // ---------- 1) 单音 ----------
        $display("  -- press key0 (C4) --");
        press(3'd0, 7'd60);
        run_n(2000);                       // 等起音 + 衰减
        clear_win; run_n(2000);
        show_win("single note");
        if (w_x != 0) begin
            $display("  FAIL  x propagated into mixer output");
            errors = errors + 1;
        end
        if (w_max - w_min < 4000) begin
            $display("  FAIL  single note too quiet: peak-to-peak=%0d", w_max - w_min);
            errors = errors + 1;
        end else begin
            $display("  ok    single note audible (p2p=%0d)", w_max - w_min);
        end

        // ---------- 2) 加满四声部和弦 ----------
        $display("  -- press keys 1,2,3 (E4 G4 C5) --");
        press(3'd1, 7'd64);
        press(3'd2, 7'd67);
        press(3'd3, 7'd72);
        run_n(2000);
        clear_win; run_n(2000);
        show_win("4-voice chord, gain=1.0");
        if (w_x != 0) begin
            $display("  FAIL  x in chord output");
            errors = errors + 1;
        end
        // V1.1 起 mixer 内部先 >>2 留余量，4 路满幅在 gain=1.0 下也不该削顶
        if (clip_count != 0) begin
            $display("  FAIL  chord clipped at gain=1.0 (clips=%0d) - headroom broken", clip_count);
            errors = errors + 1;
        end else begin
            $display("  ok    no clipping at gain=1.0 (>>2 headroom works)");
        end

        // ---------- 3) 降低总音量：整体变轻，且仍然不削顶 ----------
        $display("  -- lower gain to 0.25 (16384) --");
        master_gain = 16'd16384;
        clear_win; run_n(2000);
        show_win("4-voice chord, gain=0.25");
        if (clip_count != 0) begin
            $display("  FAIL  clipped at gain=0.25 (%0d)", clip_count);
            errors = errors + 1;
        end else begin
            $display("  ok    no clipping at gain=0.25");
        end
        if ((w_max - w_min) < 4000) begin
            $display("  FAIL  chord too quiet at gain=0.25: p2p=%0d", w_max - w_min);
            errors = errors + 1;
        end else begin
            $display("  ok    chord still audible at gain=0.25 (p2p=%0d)", w_max - w_min);
        end

        // ---------- 4) 第 5 个键：偷声部 ----------
        $display("  -- press key4 (A4) with 4 voices busy --");
        master_gain = 16'd16384;
        press(3'd4, 7'd69);
        run_n(1000);
        clear_win; run_n(2000);
        show_win("after stealing");
        if (w_x != 0) begin
            $display("  FAIL  x after stealing a voice");
            errors = errors + 1;
        end
        if (w_max - w_min < 4000) begin
            $display("  FAIL  sound lost after stealing");
            errors = errors + 1;
        end else begin
            $display("  ok    still sounding after voice steal");
        end

        // ---------- 5) 全部松开，必须真的静音 ----------
        $display("  -- release all --");
        release_key(3'd0); release_key(3'd1); release_key(3'd2);
        release_key(3'd3); release_key(3'd4);
        run_n(40000);                      // 足够放完 release 尾音
        clear_win; run_n(2000);
        show_win("after release");
        if (w_max != 0 || w_min != 0) begin
            $display("  FAIL  not silent after release: [%0d, %0d]", w_min, w_max);
            errors = errors + 1;
        end else begin
            $display("  ok    fully silent after release (no stuck note)");
        end

        // ---------- 6) 换音色再弹一次 ----------
        $display("  -- press with square timbre --");
        timbre = 2'd1;
        press(3'd0, 7'd60);
        run_n(2000);
        clear_win; run_n(2000);
        show_win("square timbre");
        if (w_x != 0 || (w_max - w_min) < 4000) begin
            $display("  FAIL  square timbre not working");
            errors = errors + 1;
        end else begin
            $display("  ok    square timbre audible (p2p=%0d)", w_max - w_min);
        end
        release_key(3'd0);

        $display("=== %0s (%0d errors) ===", (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

endmodule
`default_nettype wire
