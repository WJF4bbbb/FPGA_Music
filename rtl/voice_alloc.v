// Owner: B
// STATUS: W2 implemented. Key-identity tracking + deterministic stealing.
// See docs/interfaces.md before changing ports.
//
// 这个模块在干什么（大白话）：
//   4 把椅子，8 个客人（琴键）随时来随时走。它负责决定"谁坐哪把椅子"，
//   并且记住哪把椅子坐的是谁 —— 否则客人走了你不知道该腾哪把。
//
// 四条必须处理好的情况：
//   1. 同一个键按两下 -> 必须坐回原来那把，不能又占一把新的
//      （否则连按几下就把椅子占满了）
//   2. 松键 -> 只让"占着这个键"的那把椅子释放，别动别人的
//   3. 椅子满了 -> 先抢"已经松手、还在放释放尾音"的椅子；
//      都还在响就偷"最早被分配"的那把（用时间戳比较，结果确定）
//   4. 键被偷走后，那个键的松键事件必须**无害地忽略**，
//      不能把偷来的椅子又释放掉
`default_nettype none
module voice_alloc #(parameter NVOICE = 4) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 evt_valid,
    output wire                 evt_ready,
    input  wire [2:0]           evt_key_id,
    input  wire [6:0]           evt_note,
    input  wire                 evt_on,
    input  wire [NVOICE-1:0]    voice_busy,
    input  wire [NVOICE-1:0]    env_done,
    output wire [NVOICE*7-1:0]  voice_note,
    output wire [NVOICE-1:0]    voice_gate,
    output wire [NVOICE-1:0]    voice_trigger
);

    // ---- 每路声部的状态 ----
    reg [6:0]  v_note  [0:NVOICE-1];   // 这一路当前发什么音
    reg [2:0]  v_key   [0:NVOICE-1];   // 这一路归哪个物理键
    reg        v_key_v [0:NVOICE-1];   // v_key 是否有效（键位占用标志）
    reg [31:0] v_stamp [0:NVOICE-1];   // 分配时间戳，越小越老
    reg        v_gate  [0:NVOICE-1];   // 送给 adsr 的 gate
    reg        v_trig  [0:NVOICE-1];   // 送给 adsr 的 trigger（单拍脉冲）

    reg [31:0] seq;                    // 全局事件序号，单调递增

    // 打包成接口要求的扁平位向量：voice_note[i*7 +: 7]
    genvar gi;
    generate
        for (gi = 0; gi < NVOICE; gi = gi + 1) begin : g_pack
            assign voice_note[gi*7 +: 7] = v_note[gi];
            assign voice_gate[gi]        = v_gate[gi];
            assign voice_trigger[gi]     = v_trig[gi];
        end
    endgenerate

    // 本模块一拍就能处理完一个事件，永远准备好接收
    assign evt_ready = 1'b1;

    // ---- 分配逻辑 ----
    // 用 sel/sel_v 而不是 integer 的 -1，综合器更容易处理
    integer i;
    reg [2:0]  sel;
    reg        sel_v;
    reg [31:0] best;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seq <= 32'd0;
            for (i = 0; i < NVOICE; i = i + 1) begin
                v_note[i]  <= 7'd60;
                v_key[i]   <= 3'd0;
                v_key_v[i] <= 1'b0;
                v_stamp[i] <= 32'd0;
                v_gate[i]  <= 1'b0;
                v_trig[i]  <= 1'b0;
            end
        end else begin
            // trigger 是单拍脉冲，默认清零
            for (i = 0; i < NVOICE; i = i + 1)
                v_trig[i] <= 1'b0;

            // 释放尾音放完 -> 解除键位占用，这样这个键再来会重新分配
            for (i = 0; i < NVOICE; i = i + 1)
                if (env_done[i]) v_key_v[i] <= 1'b0;

            if (evt_valid) begin
                seq <= seq + 32'd1;

                if (evt_on) begin
                    sel_v = 1'b0;
                    sel   = 3'd0;

                    // 1) 这个键已经占着某一路？优先复用
                    for (i = 0; i < NVOICE; i = i + 1)
                        if (!sel_v && v_key_v[i] && (v_key[i] == evt_key_id)) begin
                            sel   = i;
                            sel_v = 1'b1;
                        end

                    // 2) 找完全空闲的路（没在响，也没有释放尾音）
                    if (!sel_v)
                        for (i = 0; i < NVOICE; i = i + 1)
                            if (!sel_v && !v_gate[i] && !voice_busy[i]) begin
                                sel   = i;
                                sel_v = 1'b1;
                            end

                    // 3) 全忙：先抢"已松手但尾音未放完"的路里最老的一条
                    if (!sel_v) begin
                        best = 32'hFFFFFFFF;
                        for (i = 0; i < NVOICE; i = i + 1)
                            if (!v_gate[i] && (v_stamp[i] < best)) begin
                                best  = v_stamp[i];
                                sel   = i;
                                sel_v = 1'b1;
                            end
                    end

                    // 4) 还在响的也都满了：偷最老的那一路
                    if (!sel_v) begin
                        best = 32'hFFFFFFFF;
                        for (i = 0; i < NVOICE; i = i + 1)
                            if (v_stamp[i] < best) begin
                                best  = v_stamp[i];
                                sel   = i;
                                sel_v = 1'b1;
                            end
                    end

                    // 落到某一路，配置它
                    if (sel_v) begin
                        v_note[sel]  <= evt_note;
                        v_key[sel]   <= evt_key_id;
                        v_key_v[sel] <= 1'b1;
                        v_stamp[sel] <= seq;        // 记下分配时刻，用于偷声部
                        v_gate[sel]  <= 1'b1;
                        v_trig[sel]  <= 1'b1;       // 触发一次起音
                    end
                end else begin
                    // 松键：只释放"占着这个键"的那一路。
                    // 键已被偷走时这里找不到匹配 -> 什么也不做，正好符合预期。
                    for (i = 0; i < NVOICE; i = i + 1)
                        if (v_key_v[i] && (v_key[i] == evt_key_id))
                            v_gate[i] <= 1'b0;
                end
            end
        end
    end

endmodule
`default_nettype wire
