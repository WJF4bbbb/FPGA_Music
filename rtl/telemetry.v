`timescale 1ns/1ps
`default_nettype none
// Passive 512-sample audio snapshots and unchanged 30 Hz status on one UART.
// Complete packets are arbitrated; a pending status has priority over the next
// waveform chunk. Acquisition never stalls audio. Frozen RAM is released only
// after the last chunk's CRC is queued to the UART.
module telemetry #(
    parameter integer CLK_HZ=27000000,
    parameter integer BAUD=115200,
    parameter integer NVOICE=4,
    parameter integer SAMPLE_HZ=46875,
    parameter integer WAVE_HZ=8,
    parameter integer WAVE_ENABLE=1
) (
    input wire clk,
    input wire rst_n,
    input wire [15:0] touch_keys,
    input wire [NVOICE*7-1:0] voice_note,
    input wire [NVOICE-1:0] voice_gate,
    input wire [1:0] timbre,
    input wire signed [3:0] bend,
    input wire [15:0] master_gain,
    input wire [31:0] clip_count,
    input wire signed [15:0] sample,
    input wire sample_valid,
    output wire tx,
    output wire tx_busy
);
    localparam integer SNAP_DIV=(CLK_HZ/30>0)?CLK_HZ/30:1;
    localparam integer WAVE_DIV=(CLK_HZ/WAVE_HZ>0)?CLK_HZ/WAVE_HZ:1;
    reg [31:0] tick,wave_tick;
    wire snap_pulse=(tick==SNAP_DIV-1);
    wire wave_pulse=(wave_tick==WAVE_DIV-1);
    wire capture_ready,capture_busy,capture_triggered;
    reg release_capture;
    wire capture_start=WAVE_ENABLE && wave_pulse && !capture_busy && !capture_ready && !release_capture;
    reg [15:0] capture_id,next_capture_id;
    wire signed [15:0] capture_data;
    reg [8:0] wave_offset;
    reg [8:0] byte_idx;
    wire [8:0] capture_read_addr=wave_offset+((byte_idx-9'd16)>>1);
    wave_capture u_capture (
        .clk(clk),.rst_n(rst_n),.start(capture_start),.release_capture(release_capture),
        .sample(sample),.sample_valid(sample_valid),.read_addr(capture_read_addr),
        .read_data(capture_data),.ready(capture_ready),.busy(capture_busy),.triggered(capture_triggered)
    );

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tick<=0;wave_tick<=0;capture_id<=0;next_capture_id<=0;
        end else begin
            tick<=snap_pulse?32'd0:tick+32'd1;
            wave_tick<=wave_pulse?32'd0:wave_tick+32'd1;
            if(capture_start) begin
                capture_id<=next_capture_id;
                next_capture_id<=next_capture_id+16'd1;
            end
        end
    end

    reg status_pending;
    reg [15:0] s_keys,s_gain;
    reg [27:0] s_notes;
    reg [3:0] s_gates,s_bend;
    reg [1:0] s_timbre;
    reg [31:0] s_clip;
    reg sending,packet_wave;
    reg [7:0] payload_length,chunk_samples;
    reg [7:0] packet_crc,tx_data;
    reg tx_send;
    wire tx_busy_int;
    wire [8:0] last_index={1'b0,payload_length}+9'd4;
    wire [9:0] next_offset={1'b0,wave_offset}+{2'b0,chunk_samples};

    function [7:0] crc8_step;
        input [7:0] value;
        input [7:0] previous;
        integer k;
        reg [7:0] x;
        begin
            x=previous^value;
            for(k=0;k<8;k=k+1) x=x[7]?((x<<1)^8'h07):(x<<1);
            crc8_step=x;
        end
    endfunction

    function [7:0] status_byte;
        input [8:0] index;
        begin
            case(index)
                9'd4:status_byte=s_keys[7:0];
                9'd5:status_byte=s_keys[15:8];
                9'd6:status_byte={1'b0,s_notes[6:0]};
                9'd7:status_byte={1'b0,s_notes[13:7]};
                9'd8:status_byte={1'b0,s_notes[20:14]};
                9'd9:status_byte={1'b0,s_notes[27:21]};
                9'd10:status_byte={4'b0,s_gates};
                9'd11:status_byte={6'b0,s_timbre};
                9'd12:status_byte={{4{s_bend[3]}},s_bend};
                9'd13:status_byte=s_gain[7:0];
                9'd14:status_byte=s_gain[15:8];
                9'd15:status_byte=s_clip[7:0];
                9'd16:status_byte=s_clip[15:8];
                9'd17:status_byte=s_clip[23:16];
                9'd18:status_byte=s_clip[31:24];
                default:status_byte=0;
            endcase
        end
    endfunction

    reg [7:0] next_byte;
    always @* begin
        if(byte_idx==0) next_byte=8'haa;
        else if(byte_idx==1) next_byte=8'h55;
        else if(byte_idx==2) next_byte=packet_wave?8'h10:8'h01;
        else if(byte_idx==3) next_byte=payload_length;
        else if(byte_idx==last_index) next_byte=packet_crc;
        else if(!packet_wave) next_byte=status_byte(byte_idx);
        else begin
            case(byte_idx)
                9'd4:next_byte=8'd1;
                9'd5:next_byte={7'd0,capture_triggered};
                9'd6:next_byte=capture_id[7:0];
                9'd7:next_byte=capture_id[15:8];
                9'd8:next_byte=8'h00; // total count 512, LE
                9'd9:next_byte=8'h02;
                9'd10:next_byte=wave_offset[7:0];
                9'd11:next_byte={7'd0,wave_offset[8]};
                9'd12:next_byte=SAMPLE_HZ & 255;
                9'd13:next_byte=(SAMPLE_HZ>>8) & 255;
                9'd14:next_byte=(SAMPLE_HZ>>16) & 255;
                9'd15:next_byte=(SAMPLE_HZ>>24) & 255;
                default:next_byte=byte_idx[0]?capture_data[15:8]:capture_data[7:0];
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            status_pending<=0;sending<=0;packet_wave<=0;byte_idx<=0;
            wave_offset<=0;release_capture<=0;payload_length<=15;chunk_samples<=0;
            packet_crc<=0;tx_data<=0;tx_send<=0;
            s_keys<=0;s_notes<=0;s_gates<=0;s_timbre<=0;s_bend<=0;s_gain<=0;s_clip<=0;
        end else begin
            tx_send<=0;
            release_capture<=0;
            if(snap_pulse) status_pending<=1;
            if(!sending) begin
                // tx_send guards the launch cycle of a previous final CRC.
                // release_capture guards the RAM ready signal clearing a cycle later.
                if(!tx_send && (status_pending || snap_pulse)) begin
                    s_keys<=touch_keys;s_notes<=voice_note;s_gates<=voice_gate;
                    s_timbre<=timbre;s_bend<=bend;s_gain<=master_gain;s_clip<=clip_count;
                    status_pending<=0;packet_wave<=0;payload_length<=15;
                    sending<=1;byte_idx<=0;packet_crc<=0;
                end else if(!tx_send && !release_capture && capture_ready) begin
                    packet_wave<=1;
                    chunk_samples<=(wave_offset>9'd392)?8'd32:8'd120;
                    payload_length<=(wave_offset>9'd392)?8'd76:8'd252;
                    sending<=1;byte_idx<=0;packet_crc<=0;
                end
            end else if(!tx_busy_int && !tx_send) begin
                tx_data<=next_byte;
                tx_send<=1;
                if(byte_idx>=2 && byte_idx<last_index)
                    packet_crc<=crc8_step(next_byte,packet_crc);
                if(byte_idx==last_index) begin
                    sending<=0;
                    if(packet_wave) begin
                        if(next_offset==10'd512) begin
                            wave_offset<=0;
                            release_capture<=1;
                        end else wave_offset<=next_offset[8:0];
                    end
                end else byte_idx<=byte_idx+9'd1;
            end
        end
    end
    uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_tx (
        .clk(clk),.rst_n(rst_n),.data(tx_data),.send(tx_send),.tx(tx),.busy(tx_busy_int)
    );
    assign tx_busy=tx_busy_int;
endmodule
`default_nettype wire
