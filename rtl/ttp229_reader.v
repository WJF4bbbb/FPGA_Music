`timescale 1ns/1ps
`default_nettype none
// TTP229-BSF V1.1 pp7-8, dedicated 2-wire protocol (not I2C).
// Default: idle SCL high; each falling edge presents TP0..TP15 in order.
// Sample at the END of LOW, after device propagation and two-flop SDO sync.
// A >2 ms idle interval re-aligns the peripheral before every new frame.
// keys_valid means a complete frame has been acquired, NOT device presence or
// electrical integrity: the BSF protocol has no ACK, address or checksum.
module ttp229_reader #(
    parameter integer STARTUP_CYCLES=13500000, // 0.5 s at 27 MHz
    parameter integer SCL_HALF_CYCLES=135,    // 5 us, 100 kHz
    parameter integer FRAME_GAP_CYCLES=81000, // 3 ms, >typical 2 ms timeout
    parameter ACTIVE_LOW=1
) (
    input wire clk,
    input wire rst_n,
    input wire sdo,
    output reg scl,
    output reg [15:0] keys_state,
    output reg keys_valid,
    output reg keys_commit
);
    function integer width_for;
        input integer value;
        integer n;
        begin
            width_for=1;
            for(n=value-1;n>1;n=n>>1) width_for=width_for+1;
        end
    endfunction
    localparam integer LONG_WAIT = STARTUP_CYCLES>FRAME_GAP_CYCLES ? STARTUP_CYCLES : FRAME_GAP_CYCLES;
    localparam integer MAX_WAIT = LONG_WAIT>SCL_HALF_CYCLES ? LONG_WAIT : SCL_HALF_CYCLES;
    localparam integer TIMER_W=width_for(MAX_WAIT);
    localparam [1:0] STARTUP=2'd0,GAP=2'd1,LOW_PHASE=2'd2,HIGH_PHASE=2'd3;
    reg [1:0] state;
    reg [TIMER_W-1:0] timer;
    // 抗误报补丁（全 1 过滤 + 3 帧去抖）在诊断期间临时移除，直接观察原始 frame_now。
    wire [15:0] frame_now = {pressed, shift_keys[14:0]};
    reg [3:0] bit_index;
    reg [15:0] shift_keys;
    (* syn_preserve=1, syn_keep=1, async_reg="true" *) reg sdo_meta,sdo_sync;
    // 板载 TTP229-BSF：SDO 空闲高、按下低（与约束注释 "idle high" 一致）。
    // 关键坑：Tang Nano 20K 板载 LED 是"低电平点亮"，之前用 LED 观察触摸位时把
    // "按下=亮/灭"的方向看反了，误把数据极性判反，改成了 pressed=sdo_sync，
    // 结果上电时 8 个音符键全被当成"按住"（恒音高），按键反而变"松开"（无声）。
    // 恢复为 GitHub 原始：ACTIVE_LOW=1 时 pressed = ~sdo_sync，按下=1。
    wire pressed = ACTIVE_LOW ? ~sdo_sync : sdo_sync;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sdo_meta<=ACTIVE_LOW ? 1'b1 : 1'b0;
            sdo_sync<=ACTIVE_LOW ? 1'b1 : 1'b0;
        end else begin
            sdo_meta<=sdo;
            sdo_sync<=sdo_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            scl<=ACTIVE_LOW ? 1'b1 : 1'b0;
            keys_state<=16'd0;
            keys_valid<=1'b0;
            keys_commit<=1'b0;
            state<=STARTUP;
            timer<=0;
            bit_index<=0;
            shift_keys<=0;
        end else begin
            keys_commit<=1'b0;
            case(state)
                STARTUP: begin
                    if(timer==STARTUP_CYCLES-1) begin timer<=0;state<=GAP;end
                    else timer<=timer+1'b1;
                end
                GAP: begin
                    if(timer==FRAME_GAP_CYCLES-1) begin
                        timer<=0;bit_index<=0;shift_keys<=0;
                        scl<=ACTIVE_LOW ? 1'b0 : 1'b1;
                        state<=LOW_PHASE;
                    end else timer<=timer+1'b1;
                end
                LOW_PHASE: begin
                    if(timer==SCL_HALF_CYCLES-1) begin
                        timer<=0;
                        shift_keys[bit_index]<=pressed;
                        scl<=ACTIVE_LOW ? 1'b1 : 1'b0;
                        if(bit_index==15) begin
                            keys_state<=frame_now;   // 诊断：每帧直接更新原始值
                            keys_valid<=1'b1;
                            keys_commit<=1'b1;
                            state<=GAP;
                        end else state<=HIGH_PHASE;
                    end else timer<=timer+1'b1;
                end
                HIGH_PHASE: begin
                    if(timer==SCL_HALF_CYCLES-1) begin
                        timer<=0;bit_index<=bit_index+1'b1;
                        scl<=ACTIVE_LOW ? 1'b0 : 1'b1;
                        state<=LOW_PHASE;
                    end else timer<=timer+1'b1;
                end
                default: begin
                    // Discard any incomplete frame and allow a full idle reset.
                    scl<=ACTIVE_LOW ? 1'b1 : 1'b0;
                    timer<=0;state<=GAP;
                    keys_valid<=1'b0;keys_state<=0;shift_keys<=0;bit_index<=0;
                end
            endcase
        end
    end
    // synthesis translate_off
    initial begin
        if(STARTUP_CYCLES<1 || SCL_HALF_CYCLES<4 || FRAME_GAP_CYCLES<1) begin
            $display("FAIL: invalid TTP229 timing parameters");$finish;
        end
    end
    // synthesis translate_on
endmodule
`default_nettype wire
