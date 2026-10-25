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
// 事件处理（这是接口合同里明确要求的）：
//   trigger 是单拍脉冲，可能落在两个样本之间 —— 必须先锁存，
//   到下一个 wave_valid（样本边界）再消费，否则会丢音。
//
// 实现要点：包络的"下一状态"和"下一电平"先用阻塞赋值算进临时变量，
//   再用**更新后的电平**算输出。这样释放结束时输出正好是 0，
//   不会残留一个尾巴样本。
`default_nettype none
module adsr #(parameter FS_HZ = 46875) (
    input  wire               clk,
    input  wire               rst_n,
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

    reg               trig_lat;     // trigger 锁存
    reg               rel_lat;      // 松键事件锁存
    reg               gate_d;       // 上一拍的 gate，用来抓下降沿

    reg signed [15:0] sample_r;
    reg               valid_r;
    reg               done_r;

    // 组合临时变量（阻塞赋值，只在时钟块里用）
    reg [2:0]         st_nxt;
    reg signed [15:0] lvl_nxt;
    reg               done_nxt;
    reg signed [31:0] prod_nxt;

    // 锁存值与本拍事件合并，保证"同一拍到达"也不会漏
    wire trig_now = trig_lat | trigger;
    wire rel_now  = (rel_lat | (gate_d & ~gate)) & (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            level     <= 16'sd0;
            trig_lat  <= 1'b0;
            rel_lat   <= 1'b0;
            gate_d    <= 1'b0;
            sample_r  <= 16'sd0;
            valid_r   <= 1'b0;
            done_r    <= 1'b0;
        end else begin
            gate_d <= gate;
            done_r <= 1'b0;             // 默认无完成脉冲

            // ---- 事件锁存：只在样本边界消费 ----
            if (wave_valid) begin
                trig_lat <= 1'b0;
                rel_lat  <= 1'b0;
            end else begin
                if (trigger)        trig_lat <= 1'b1;
                if (gate_d & ~gate) rel_lat  <= 1'b1;
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
