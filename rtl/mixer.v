// Owner: B
// STATUS: W2 implemented. N-lane signed sum + headroom + master_gain + saturation.
//         端口已按 docs/interfaces.md V1.1 对齐：新增 frame_tick，在它上面锁存总音量。
//
// 关键点（这是本模块唯一容易错的地方）：
//   16 位有符号数相加，结果会超出 16 位范围。如果直接截断低 16 位，
//   超过 +32767 的数会"回绕"成负数 —— 听感上是刺耳的撕裂爆音，
//   评分里明确禁止。所以必须先加宽、再饱和（clamp）到 [-32768, 32767]。
//
//   另外 4 路同时满幅时总和是 4 倍满幅，直接乘增益必然削顶。
//   所以先右移 log2(NVOICE) 留出余量（4 路 >>2，8 路 >>3），再乘总音量。
`default_nettype none
module mixer #(parameter NVOICE = 4) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     frame_tick,
    input  wire [NVOICE*16-1:0]     voice_samples,
    input  wire [NVOICE-1:0]        voice_valid,
    input  wire [15:0]              master_gain,
    output wire signed [15:0]       sample,
    output wire                     valid,
    output wire [31:0]              clip_count
);

    // ---- 1) + 2) 逐路取出有符号样本并宽累加 ----
    // 24 位足够容纳 NVOICE 路 16 位有符号之和（4 路最大 ±131068，只要 18 位）。
    // 用 24 位是为了给将来的 8 复音留余量，且不增加多少资源。
    //
    // 注意：这里刻意**直接读端口**，不经过中间 wire。
    // 如果先 assign 出一组 lane[] 再在 always 里读，敏感列表只有端口，
    // 而 lane[] 要晚一个 delta 周期才稳定 —— 累加会读到 x，之后又不会重新触发。
    // 这是仿真里非常隐蔽的一类错，所以宁可把读取写在循环里。
    reg signed [23:0] acc;
    integer i;
    always @(voice_samples or voice_valid) begin
        acc = 24'sd0;
        for (i = 0; i < NVOICE; i = i + 1) begin
            if (voice_valid[i])
                acc = acc + $signed(voice_samples[i*16 +: 16]);   // 两边有符号，自动符号扩展
        end
    end

    // ---- 3) 留余量 + 乘总音量 ----
    // master_gain 是 0..65535 的无符号数，65536 才等于 1.0（Q16 定点）。
    // 这里先零扩展成 17 位有符号（保证是非负数），再乘，结果才有符号。
    //
    // 总音量在 frame_tick 那一拍定格：一帧之内旋钮再动，本帧用的还是旧值，
    // 避免同一帧里四个声部用了不同的增益。
    reg [15:0] gain_lat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          gain_lat <= 16'd0;
        else if (frame_tick) gain_lat <= master_gain;
    end

    // 4 路同时满幅 -> 总和约 4 倍满幅；先 >>2 把余量留出来（8 路 >>3）。
    localparam integer SUM_SHIFT = (NVOICE >= 8) ? 3 : 2;

    wire signed [23:0] acc_sh = acc >>> SUM_SHIFT;          // 算术右移，负数也正确
    wire signed [16:0] gain_s = $signed({1'b0, gain_lat});

    // 24 + 17 = 41 位；用 wire 承接，LHS 宽度就是 41，乘法不会被提前截断
    wire signed [40:0] prod   = acc_sh * gain_s;

    // 右移 16 位还原定标。>>> 是算术右移，负数也正确。
    wire signed [24:0] scaled = prod >>> 16;

    // ---- 4) 饱和截断 + 输出寄存 ----
    reg signed [15:0] sample_r;
    reg               valid_r;
    reg [31:0]        clip_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_r <= 16'sd0;
            valid_r  <= 1'b0;
            clip_cnt <= 32'd0;
        end else if (|voice_valid) begin
            // 只有"本帧有效"这一拍才评估。voice_valid 是一拍脉冲，
            // 若不加这个门控，同一帧的和会在 576 个时钟里被反复判定，
            // clip_count 会凭空涨 576 倍。
            valid_r <= 1'b1;
            if (scaled > 25'sd32767) begin
                sample_r <= 16'sh7FFF;              // 正溢出：停在 +32767
                clip_cnt <= clip_cnt + 32'd1;
            end else if (scaled < -25'sd32768) begin
                sample_r <= 16'sh8000;              // 负溢出：停在 -32768
                clip_cnt <= clip_cnt + 32'd1;
            end else begin
                sample_r <= scaled[15:0];           // 范围内，直接取低 16 位
            end
        end else begin
            valid_r <= 1'b0;
            // 无新帧时保持上一帧的样本，供 i2s_tx 在整帧内取用
        end
    end

    assign sample     = sample_r;
    assign valid      = valid_r;
    assign clip_count = clip_cnt;

endmodule
`default_nettype wire
