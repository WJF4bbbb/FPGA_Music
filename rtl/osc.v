// Owner: B
// STATUS: W1 DDS + W3 timbre(4 waveforms) + bend(+-2 semitones) done.
//         端口已按 docs/interfaces.md V1.1 对齐：采样节拍信号名为 frame_tick
//         （来自 audio_timing），每次 frame_tick 推进一次相位并输出一拍 valid。
//
// 这个模块在干什么（大白话）：
//   一个转盘 + 一张对照表。指针（phase）每个采样点往前走一步（fcw），
//   走到哪就取哪一格的波形值。转一圈 = 一个声音周期，转得快 = 音高。
//
// 两个"维度"的实现方式：
//   音色 timbre  -> 换对照表（正弦/方波/锯齿/三角），不影响相位
//   变调 bend    -> 改变每步走多远（乘一个半音比例），**绝不清相位**
//                   （清相位会在变调瞬间产生台阶，听感上是"咔"一声）
`default_nettype none
module osc #(parameter FS_HZ = 46875) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               frame_tick,
    input  wire [6:0]         note,
    input  wire signed [3:0]  bend,
    input  wire [1:0]         timbre,
    output wire signed [15:0] wave,
    output wire               valid
);

    reg  [31:0]        phase;
    reg  signed [15:0] wave_r;
    reg                valid_r;

    wire [7:0]         lut_addr;
    wire signed [15:0] lut_dout;

    // 用相位的高 8 位当表地址：2^32 / 256 = 每步 16777216
    assign lut_addr = phase[31:24];

    sin_rom u_sin_rom (
        .addr (lut_addr),
        .dout (lut_dout)
    );

    // note -> FCW,  FCW = round( f * 2^32 / FS_HZ ),  f = 440 * 2^((note-69)/12)
    //
    // 这里刻意写成 function，而不是独立的 always @* 组合块。原因：
    // Icarus 12.0 在 -g2012 下，若某个输入在声明处初始化后不再变化，
    // always @* 不会在时刻 0 触发，fcw 会一直停在 x —— 而且**不报错**，
    // 仿真结果只是静默变成全 0。function 在时序块里调用，两种语言模式
    // 行为一致，同样可综合，没有这个坑。
    function [31:0] note_to_fcw;
        input [6:0] n;
        begin
            case (n)
                7'd60: note_to_fcw = 32'd23971696;   // 261.63 Hz  C4
                7'd61: note_to_fcw = 32'd25397127;   // 277.18 Hz
                7'd62: note_to_fcw = 32'd26907319;   // 293.66 Hz
                7'd63: note_to_fcw = 32'd28507311;   // 311.13 Hz
                7'd64: note_to_fcw = 32'd30202444;   // 329.63 Hz  E4
                7'd65: note_to_fcw = 32'd31998375;   // 349.23 Hz
                7'd66: note_to_fcw = 32'd33901097;   // 369.99 Hz
                7'd67: note_to_fcw = 32'd35916962;   // 392.00 Hz  G4
                7'd68: note_to_fcw = 32'd38052695;   // 415.30 Hz
                7'd69: note_to_fcw = 32'd40315426;   // 440.00 Hz  A4
                7'd70: note_to_fcw = 32'd42712706;   // 466.16 Hz
                7'd71: note_to_fcw = 32'd45252536;   // 493.88 Hz
                7'd72: note_to_fcw = 32'd47943392;   // 523.25 Hz  C5
                default: note_to_fcw = 32'd23971696;
            endcase
        end
    endfunction

    // 半音变调比例，Q16 定点（65536 = 1.0 = 不弯）
    //   2^(n/12) * 65536, n = -2..+2
    function [16:0] bend_ratio;
        input signed [3:0] b;
        begin
            case (b)
                 4'sd0:  bend_ratio = 17'd65536;   // 1.000000
                 4'sd1:  bend_ratio = 17'd69433;   // 1.059463  +1 半音
                 4'sd2:  bend_ratio = 17'd73562;   // 1.122462  +2 半音
                -4'sd1:  bend_ratio = 17'd61857;   // 0.943874  -1 半音
                -4'sd2:  bend_ratio = 17'd58385;   // 0.890899  -2 半音
                default: bend_ratio = 17'd65536;
            endcase
        end
    endfunction

    // 32 x 17 = 49 位乘积，右移 16 位还原成 32 位 FCW。
    // 用 wire 承接，LHS 宽度 49 位，乘法不会被提前截断。
    // 27MHz 下这个组合路径余量充足；若将来时序吃紧，把 fcw_bent 打一拍即可。
    wire [48:0] fcw_prod = note_to_fcw(note) * bend_ratio(bend);
    wire [31:0] fcw_bent = fcw_prod[47:16];

    // 波形选择：同一个相位，四种"对照表"
    //   正弦 = ROM 查表
    //   方波 = 看最高位（前半周期 +满，后半周期 -满）
    //   锯齿 = 相位线性映射到 -32768..+32767（最高位取反即偏移二进制转补码）
    //   三角 = 前半周期爬升、后半周期折返
    function signed [15:0] wave_of;
        input [1:0]         t;
        input [31:0]        ph;
        input signed [15:0] sn;
        reg   [15:0]        raw;
        begin
            case (t)
                2'd0: wave_of = sn;                                 // 正弦
                2'd1: wave_of = ph[31] ? 16'sh8000 : 16'sh7FFF;      // 方波
                2'd2: wave_of = {~ph[31], ph[30:16]};                // 锯齿
                2'd3: begin                                          // 三角
                          raw     = ph[31] ? ~ph[30:15] : ph[30:15];
                          wave_of = {~raw[15], raw[14:0]};
                      end
                default: wave_of = sn;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase   <= 32'd0;
            wave_r  <= 16'sd0;
            valid_r <= 1'b0;
        end else begin
            valid_r <= 1'b0;
            if (frame_tick) begin
                phase   <= phase + fcw_bent;                    // 相位累加：加得快 = 音高
                wave_r  <= wave_of(timbre, phase, lut_dout);    // 用当前相位取波形
                valid_r <= 1'b1;
            end
        end
    end

    assign wave  = wave_r;
    assign valid = valid_r;

endmodule
`default_nettype wire
