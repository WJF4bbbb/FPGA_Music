// b_top.v -- 综合自检用的临时顶层，只属于 B，不参与整机 top.v
//
// 作用：把 B 名下 4 个模块按真实数据流接起来，让高云综合器检查
//       ① 有没有不可综合的写法 ② 占多少 LUT/REG/DSP/BSRAM。
//
// 和 rtl/top.v 的区别：
//   - 这里没有按键扫描、没有 I2S、没有音色选择（那些是 A 和 C 的）
//   - 这里的 frame_tick 是本地分频出来的占位节拍，真正的 audio_timing 由 A 提供
//
// 综合入口：bash synth_check/run_synth.sh
`default_nettype none
module b_top #(
    parameter FS_HZ = 46875
) (
    input  wire               clk,          // Tang Nano 20K 板载 27MHz
    input  wire               rst_n,
    input  wire               evt_valid,    // 按键事件（正常由 note_event 驱动）
    input  wire [2:0]         evt_key_id,
    input  wire [6:0]         evt_note,
    input  wire               evt_on,       // 1=按下 0=松开
    input  wire [1:0]         timbre,
    input  wire signed [3:0]  bend,
    input  wire [15:0]        master_gain,
    output wire signed [15:0] audio_out,
    output wire               audio_valid,
    output wire [31:0]        clip_count,
    output wire [3:0]         voice_led    // 4 路占用指示，现场可接 LED
);

    // ---- 占位采样节拍：27MHz / 576 = 46875 Hz ----
    reg [9:0] div_cnt;
    reg       frame_tick;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt   <= 10'd0;
            frame_tick <= 1'b0;
        end else if (div_cnt == 10'd575) begin
            div_cnt   <= 10'd0;
            frame_tick <= 1'b1;
        end else begin
            div_cnt   <= div_cnt + 10'd1;
            frame_tick <= 1'b0;
        end
    end

    wire [27:0] v_note;
    wire [3:0]  v_gate, v_trig, v_busy, v_env_done, s_valid;
    wire [63:0] wave_flat, samp_flat;

    voice_alloc #(.NVOICE(4)) u_va (
        .clk           (clk),
        .rst_n         (rst_n),
        .evt_valid     (evt_valid),
        .evt_ready     (),
        .evt_key_id    (evt_key_id),
        .evt_note      (evt_note),
        .evt_on        (evt_on),
        .voice_busy    (v_busy),
        .env_done      (v_env_done),
        .voice_note    (v_note),
        .voice_gate    (v_gate),
        .voice_trigger (v_trig)
    );

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : g_voice
            osc #(.FS_HZ(FS_HZ)) u_osc (
                .clk       (clk),
                .rst_n     (rst_n),
                .frame_tick (frame_tick),
                .note      (v_note[i*7 +: 7]),
                .bend      (bend),
                .timbre    (timbre),
                .wave      (wave_flat[i*16 +: 16]),
                .valid     ()
            );
            adsr #(.FS_HZ(FS_HZ)) u_adsr (
                .clk        (clk),
                .rst_n      (rst_n),
                .frame_tick (frame_tick),
                .wave_valid (frame_tick),
                .wave       (wave_flat[i*16 +: 16]),
                .gate       (v_gate[i]),
                .trigger    (v_trig[i]),
                .sample     (samp_flat[i*16 +: 16]),
                .valid      (s_valid[i]),
                .busy       (v_busy[i]),
                .env_done   (v_env_done[i])
            );
        end
    endgenerate

    mixer #(.NVOICE(4)) u_mix (
        .clk           (clk),
        .rst_n         (rst_n),
        .frame_tick    (frame_tick),
        .voice_samples (samp_flat),
        .voice_valid   (s_valid),
        .master_gain   (master_gain),
        .sample        (audio_out),
        .valid         (audio_valid),
        .clip_count    (clip_count)
    );

    assign voice_led = v_busy;

endmodule
`default_nettype wire
