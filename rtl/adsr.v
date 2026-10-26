// Owner: B
// STATUS: W3 implemented. 5-state envelope (IDLE/ATTACK/DECAY/SUSTAIN/RELEASE).
// See docs/interfaces.md before changing ports.
//
// 为什么需要这个模块（一句话）：
//   没有包络，按键瞬间音量从 0 直接跳到满值 —— 波形出现垂直跳变，
//   喇叭会"啪"一声（pop 爆音）。ADSR 把这条跳变改成斜坡，声音才有"起音"。
//
// 电平定标：level 是 0..32767 的 Q15 增益（32767 ≈ 1.0 满幅），
//   输出 sample = wave * level >>> 15。
//
// 事件处理（V1.1 合同，改过一次，务必按这个来）：
//   gate / trigger 在 frame_tick 那一拍**定格成快照**，随后 wave_valid 到达时
//   用这份快照更新包络。这样一帧之内控制线再抖动也不会影响本帧结果。
//   trigger 可能只持续一个 clk、落在两帧之间 —— 先存进 trig_lat，
//   到下一个 frame_tick 才并入快照，所以不会丢音。
`default_nettype none
module adsr #(parameter FS_HZ = 46875) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               frame_tick,
    input  wire               wave_valid,
    input  wire signed [15:0] wave,
    input  wire               gate,
    input  wire               trigger,
    output wire signed [15:0] sample,
    output wire               valid,
    output wire               busy,
    output wire               env_done
);

    localparam [2:0] S_IDLE = 3'd0,
                     S_ATT  = 3'd1,
                     S_DEC  = 3'd2,
                     S_SUS  = 3'd3,
                     S_REL  = 3'd4;

    // ---- 各阶段时长（换算成采样点数）----
    localparam integer ATT_N = (FS_HZ / 100      < 1) ? 1 : FS_HZ / 100;      // 10 ms
    localparam integer DEC_N = (FS_HZ / 5        < 1) ? 1 : FS_HZ / 5;        // 200 ms
    localparam integer REL_N = (FS_HZ * 3 / 20   < 1) ? 1 : FS_HZ * 3 / 20;   // 150 ms

    // 每步增量 = 总变化量 / 步数，向上取整保证能在预定时间内走完
    localparam signed [15:0] SUS_LEVEL = 16'sd19660;                          // 0.6 满幅
    localparam signed [15:0] ATT_STEP  = (16'sd32767 / ATT_N) + 16'sd1;
    localparam signed [15:0] DEC_STEP  = ((16'sd32767 - SUS_LEVEL) / DEC_N) + 16'sd1;
    localparam signed [15:0] REL_STEP  = (16'sd32767 / REL_N) + 16'sd1;

    reg [2:0]         state;
    reg signed [15:0] level;        // 当前包络电平 0..32767

    reg               trig_lat;     // trigger 原始锁存（可能落在两帧之间）
    reg               trig_snap;    // frame_tick 定格的"本帧要处理的重触发"
    reg               gate_snap;    // frame_tick 定格的 gate 电平

    reg signed [15:0] sample_r;
    reg               valid_r;
    reg               done_r;

    // 组合临时变量（阻塞赋值，只在时钟块里用）
    reg [2:0]         st_nxt;
    reg signed [15:0] lvl_nxt;
    reg               done_nxt;
    reg signed [31:0] prod_nxt;

    // frame_tick 与 wave_valid 同拍时用本拍的新快照，否则用已定格的快照。
    // 这样"同一拍到达"不会漏事件，也不会把上一帧的事件重复消费。
    wire trig_eff = frame_tick ? (trig_lat | trigger) : trig_snap;
    wire gate_eff = frame_tick ? gate : gate_snap;

    wire trig_now = trig_eff;
    wire rel_now  = (state != S_IDLE) & ~gate_eff;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            level     <= 16'sd0;
            trig_lat  <= 1'b0;
            trig_snap <= 1'b0;
            gate_snap <= 1'b0;
            sample_r  <= 16'sd0;
            valid_r   <= 1'b0;
            done_r    <= 1'b0;
        end else begin
            done_r <= 1'b0;             // 默认无完成脉冲

            // ---- 事件：frame_tick 定格本帧控制，wave_valid 时消费 ----
            if (frame_tick) begin
                gate_snap <= gate;
                // 同拍若正好有 wave_valid，本帧立刻消费掉，不留到下一帧
                trig_snap <= (trig_lat | trigger) & ~wave_valid;
                trig_lat  <= 1'b0;
            end else begin
                if (trigger)    trig_lat  <= 1'b1;
                if (wave_valid) trig_snap <= 1'b0;
            end

            // ---- 每个样本更新一次包络 ----
            if (wave_valid) begin
                st_nxt   = state;       // 默认保持
                lvl_nxt  = level;
                done_nxt = 1'b0;

                if (trig_now) begin
                    // 起音。从"当前电平"继续往上爬，不清零 ——
                    // 这样偷声部或同键重按时不会有台阶，避免爆音。
                    st_nxt  = S_ATT;
                    lvl_nxt = (level > 16'sd32767 - ATT_STEP) ? 16'sd32767
                                                              : level + ATT_STEP;
                end else if (rel_now) begin
                    if (level <= REL_STEP) begin
                        lvl_nxt  = 16'sd0;          // 必须真的到 0 才算结束
                        st_nxt   = S_IDLE;
                        done_nxt = 1'b1;            // env_done 完成脉冲
                    end else begin
                        lvl_nxt = level - REL_STEP;
                        st_nxt  = S_REL;
                    end
                end else begin
                    case (state)
                        S_IDLE: lvl_nxt = 16'sd0;

                        S_ATT: begin
                            if (level > 16'sd32767 - ATT_STEP) begin
                                lvl_nxt = 16'sd32767;
                                st_nxt  = S_DEC;
                            end else begin
                                lvl_nxt = level + ATT_STEP;
                            end
                        end

                        S_DEC: begin
                            if (level < SUS_LEVEL + DEC_STEP) begin
                                lvl_nxt = SUS_LEVEL;
                                st_nxt  = S_SUS;
                            end else begin
                                lvl_nxt = level - DEC_STEP;
                            end
                        end

                        S_SUS: lvl_nxt = SUS_LEVEL;

                        S_REL: begin
                            if (level <= REL_STEP) begin
                                lvl_nxt  = 16'sd0;
                                st_nxt   = S_IDLE;
                                done_nxt = 1'b1;
                            end else begin
                                lvl_nxt = level - REL_STEP;
                            end
                        end

                        default: begin
                            lvl_nxt = 16'sd0;
                            st_nxt  = S_IDLE;
                        end
                    endcase
                end

                // 用更新后的电平算输出：释放结束那一拍输出正好是 0
                prod_nxt = wave * lvl_nxt;      // 16x16 有符号 -> 32 位，不会溢出
                sample_r <= prod_nxt[30:15];    // 算术右移 15 位 = 除以 32768
                valid_r  <= 1'b1;
                state    <= st_nxt;
                level    <= lvl_nxt;
                done_r   <= done_nxt;
            end else begin
                valid_r <= 1'b0;
            end
        end
    end

    assign sample   = sample_r;
    assign valid    = valid_r;
    assign busy     = (state != S_IDLE);   // 起音到释放结束期间都算占用
    assign env_done = done_r;

endmodule
`default_nettype wire
