`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// top_at_cfg.v —— AT 配置专用顶层（独立于正常演奏固件）
//
// 【用途】
//   只在"给 HC-05 改波特率"这一次性操作时烧录。改完就烧回正常固件。
//   不例化音频链路，不碰 TTP229，不碰 I2S，编译快、失败面小。
//
// 【引脚】见 constraints/at_cfg.cst
//   clk=4  rst_n=73  at_tx=85  at_rx=77  led[5:0]=15..20
//
// 【LED 极性】
//   唐纳诺 20K 的板载 LED 是低电平点亮（阳极接 3.3V，经 510Ω 到 IO）。
//   如果实测极性相反，把 LED_ACTIVE_LOW 改成 0 即可。
// ============================================================================
module top_at_cfg #(
    parameter integer LED_ACTIVE_LOW = 1
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       at_rx,
    output wire       at_tx,
    output wire [5:0] led
);

    // ---- 上电复位：配置完成后先压住 2.4 ms，等电源和模块都稳 ----
    reg [15:0] por;
    wire por_n = (por == 16'hFFFF);

    always @(posedge clk) begin
        if (!por_n) por <= por + 16'd1;
    end

    wire core_rst_n = rst_n & por_n;

    wire [5:0] led_hi;

    bt_at_init u_at (
        .clk  (clk),
        .rst_n(core_rst_n),
        .at_tx(at_tx),
        .at_rx(at_rx),
        .led  (led_hi),
        .done (),
        .fail ()
    );

    assign led = LED_ACTIVE_LOW ? ~led_hi : led_hi;

endmodule
`default_nettype wire
