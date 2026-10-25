// Owner: B
// STATUS: W1 DDS done (phase accumulator + 256-point sine ROM).
// TODO(W3): timbre 4 waveforms, bend (+-2 semitones) -> change FCW, never reset phase.
`default_nettype none
module osc #(parameter FS_HZ = 46875) (
    input  wire clk,
    input  wire rst_n,
    input  wire sample_en,
    input  wire [6:0] note,
    input  wire signed [3:0] bend,
    input  wire [1:0] timbre,
    output wire signed [15:0] wave,
    output wire valid
);

    reg  [31:0]        phase;
    reg  [31:0]        fcw;
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
    always @* begin
        case (note)
            7'd60: fcw = 32'd23971696;   // 261.63 Hz  C4
            7'd61: fcw = 32'd25397127;   // 277.18 Hz
            7'd62: fcw = 32'd26907319;   // 293.66 Hz
            7'd63: fcw = 32'd28507311;   // 311.13 Hz
            7'd64: fcw = 32'd30202444;   // 329.63 Hz  E4
            7'd65: fcw = 32'd31998375;   // 349.23 Hz
            7'd66: fcw = 32'd33901097;   // 369.99 Hz
            7'd67: fcw = 32'd35916962;   // 392.00 Hz  G4
            7'd68: fcw = 32'd38052695;   // 415.30 Hz
            7'd69: fcw = 32'd40315426;   // 440.00 Hz  A4
            7'd70: fcw = 32'd42712706;   // 466.16 Hz
            7'd71: fcw = 32'd45252536;   // 493.88 Hz
            7'd72: fcw = 32'd47943392;   // 523.25 Hz  C5
            default: fcw = 32'd23971696;
        endcase
    end

    // bend / timbre 暂时不用（W3 再实现），端口先留着，接口合同不能改

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase   <= 32'd0;
            wave_r  <= 16'sd0;
            valid_r <= 1'b0;
        end else begin
            valid_r <= 1'b0;
            if (sample_en) begin
                phase   <= phase + fcw;   // 相位累加：加得快 = 音高
                wave_r  <= lut_dout;      // 用当前相位查表得波形值
                valid_r <= 1'b1;
            end
        end
    end

    assign wave  = wave_r;
    assign valid = valid_r;

endmodule
`default_nettype wire
