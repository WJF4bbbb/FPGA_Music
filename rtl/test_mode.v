`timescale 1ns/1ps
`default_nettype none
// V1.1接口：enable由top在启动时锁定，切换模式必须统一复位。
// 本模块只发音符事件，不生成PCM、音频时钟或独立逻辑时钟。
module test_mode #(
    // 合法范围各为1..3728270帧，保证帧数*576在正32位integer内。
    parameter integer HOLD_FRAMES = 93750,
    parameter integer RELEASE_FRAMES = 11719
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    input  wire       evt_ready,
    output wire       evt_valid,
    output wire [2:0] evt_key_id,
    output wire [6:0] evt_note,
    output wire       evt_on
);
    localparam [2:0] IDLE=3'd0, NOTE_ON=3'd1, HOLD=3'd2,
                     NOTE_OFF=3'd3, RELEASE_WAIT=3'd4;
    localparam integer CLOCKS_PER_FRAME=576;
    localparam [31:0] HOLD_LAST=HOLD_FRAMES*CLOCKS_PER_FRAME-1;
    localparam [31:0] RELEASE_LAST=RELEASE_FRAMES*CLOCKS_PER_FRAME-1;
    localparam [1:0] LAST_KEY=2'd3;
    localparam [6:0] NOTE_C4=7'd60, NOTE_E4=7'd64,
                     NOTE_G4=7'd67, NOTE_C5=7'd72;
    reg [2:0] state;
    reg [1:0] event_index;
    reg [31:0] wait_count;
    reg [6:0] selected_note;

    always @* begin
        case(event_index)
            2'd0: selected_note=NOTE_C4;
            2'd1: selected_note=NOTE_E4;
            2'd2: selected_note=NOTE_G4;
            2'd3: selected_note=NOTE_C5;
            default: selected_note=7'd0;
        endcase
    end
    // valid不依赖ready；阻塞时state/index不变，整条事件保持稳定。
    assign evt_valid = rst_n && enable && ((state==NOTE_ON) || (state==NOTE_OFF));
    assign evt_key_id = {1'b0,event_index};
    assign evt_note = (state==IDLE) ? 7'd0 : selected_note;
    assign evt_on = (state==NOTE_ON);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= IDLE;
            event_index <= 2'd0;
            wait_count <= 32'd0;
        end else if(!enable) begin
            state <= IDLE;
            event_index <= 2'd0;
            wait_count <= 32'd0;
        end else begin
            case(state)
                IDLE: begin
                    event_index <= 2'd0;
                    wait_count <= 32'd0;
                    state <= NOTE_ON;
                end
                NOTE_ON: begin
                    if(evt_valid && evt_ready) begin
                        if(event_index==LAST_KEY) begin
                            state <= HOLD;
                            wait_count <= 32'd0;
                        end else event_index <= event_index+2'd1;
                    end
                end
                HOLD: begin
                    // 第4条Note On成功后的下一拍开始计时。
                    // V1.1无frame_tick端口，按每帧576个clk计算相同时长，
                    // 不另造音频节拍；背压时间不会侵占和弦保持时间。
                    if(wait_count==HOLD_LAST) begin
                        state <= NOTE_OFF;
                        event_index <= 2'd0;
                        wait_count <= 32'd0;
                    end else wait_count <= wait_count+32'd1;
                end
                NOTE_OFF: begin
                    if(evt_valid && evt_ready) begin
                        if(event_index==LAST_KEY) begin
                            state <= RELEASE_WAIT;
                            wait_count <= 32'd0;
                        end else event_index <= event_index+2'd1;
                    end
                end
                RELEASE_WAIT: begin
                    // 仅在全部Note Off握手完成后等待，再从完整和弦重播。
                    if(wait_count==RELEASE_LAST) begin
                        state <= NOTE_ON;
                        event_index <= 2'd0;
                        wait_count <= 32'd0;
                    end else wait_count <= wait_count+32'd1;
                end
                default: begin
                    state <= IDLE;
                    event_index <= 2'd0;
                    wait_count <= 32'd0;
                end
            endcase
        end
    end
endmodule
`default_nettype wire
