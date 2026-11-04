`timescale 1ns/1ps
`default_nettype none
module tb_telemetry_wave;
    localparam integer CLK_HZ=2700000, BAUD=115200, DIV=CLK_HZ/BAUD;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg signed [15:0] sample=0;
    reg sample_valid=0;
    wire tx,tx_busy;
    telemetry #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) dut (
        .clk(clk),.rst_n(rst_n),.touch_keys(16'ha55a),
        .voice_note({7'd72,7'd67,7'd64,7'd60}),.voice_gate(4'b1011),
        .timbre(2'd3),.bend(-4'sd2),.master_gain(16'd49152),.clip_count(32'd7),
        .sample(sample),.sample_valid(sample_valid),.tx(tx),.tx_busy(tx_busy)
    );
    function [15:0] reference_sample(input integer index);
        begin
            case(index % 8)
                0:reference_sample=16'd0;
                1:reference_sample=16'h7fff;
                2:reference_sample=16'h8000;
                3:reference_sample=16'hffff;
                4:reference_sample=16'h0001;
                5:reference_sample=16'haa55;
                6:reference_sample=16'd1234;
                7:reference_sample=-16'sd1234;
            endcase
        end
    endfunction
    function [7:0] crc_step(input [7:0] crc,input [7:0] value);
        reg [7:0] x;
        integer k;
        begin
            x=crc^value;
            for(k=0;k<8;k=k+1) x=x[7] ? (x<<1)^8'h07 : x<<1;
            crc_step=x;
        end
    endfunction
    task push(input [15:0] value);
        begin
            @(negedge clk); sample=value; sample_valid=1;
            @(negedge clk); sample_valid=0;
            repeat(2) @(negedge clk);
        end
    endtask
    integer capture_number, n;
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        for(capture_number=0;capture_number<2;capture_number=capture_number+1) begin
            @(posedge dut.capture_start);
            @(negedge clk);
            push(-16'sd3);push(-16'sd2);
            for(n=0;n<512;n=n+1) push(reference_sample(n));
            // Changing live audio must not overwrite the frozen transmission.
            @(negedge clk); sample=16'sd22222; sample_valid=1;
            repeat(10000) @(negedge clk);
            sample_valid=0;
        end
    end
    task receive_byte(output [7:0] value);
        integer b;
        begin
            @(negedge tx);
            repeat(DIV/2) @(posedge clk);
            if(tx!==0) $fatal(1,"bad UART start bit");
            for(b=0;b<8;b=b+1) begin repeat(DIV) @(posedge clk);value[b]=tx;end
            repeat(DIV) @(posedge clk);
            if(tx!==1) $fatal(1,"bad UART stop bit");
        end
    endtask
    reg [7:0] frame[0:260];
    reg [7:0] crc;
    reg [15:0] got;
    integer j,k,count,offset,expected_offset=0,expected_capture=0;
    integer status_count=0,wave_count=0,interleaved_status=0,fixture;
    initial begin
        fixture=$fopen("sim/waveform_uart.hex","w");
        wait(rst_n);
        while(expected_capture<2) begin
            for(j=0;j<4;j=j+1) receive_byte(frame[j]);
            if(frame[0]!==8'haa || frame[1]!==8'h55) $fatal(1,"outer header damaged");
            for(j=4;j<5+frame[3];j=j+1) receive_byte(frame[j]);
            crc=0;
            for(j=2;j<4+frame[3];j=j+1) crc=crc_step(crc,frame[j]);
            if(frame[4+frame[3]]!==crc) $fatal(1,"CRC mismatch type=%h",frame[2]);
            for(j=0;j<5+frame[3];j=j+1) $fdisplay(fixture,"%02x",frame[j]);
            if(frame[2]==1) begin
                status_count=status_count+1;
                if(expected_offset!=0) interleaved_status=interleaved_status+1;
                if(frame[3]!==15 || {frame[5],frame[4]}!==16'ha55a ||
                    frame[6]!==60 || frame[7]!==64 || frame[8]!==67 || frame[9]!==72 ||
                    frame[10]!==11 || frame[11]!==3 || frame[12]!==8'hfe ||
                    {frame[14],frame[13]}!==16'd49152 ||
                    {frame[18],frame[17],frame[16],frame[15]}!==32'd7)
                    $fatal(1,"status protocol compatibility failed");
            end else if(frame[2]==8'h10) begin
                wave_count=wave_count+1;
                if(frame[4]!==1 || frame[5]!==1 ||
                    {frame[7],frame[6]}!==expected_capture ||
                    {frame[9],frame[8]}!==512 ||
                    {frame[15],frame[14],frame[13],frame[12]}!==46875)
                    $fatal(1,"wave metadata mismatch");
                offset={frame[11],frame[10]};
                if(offset!=expected_offset) $fatal(1,"wave packet offset %0d expected %0d",offset,expected_offset);
                count=(frame[3]-12)/2;
                if(count!=((512-offset>120)?120:512-offset) || frame[3]!=12+2*count)
                    $fatal(1,"wave length mismatch");
                for(k=0;k<count;k=k+1) begin
                    got={frame[17+2*k],frame[16+2*k]};
                    if(got!==reference_sample(offset+k))
                        $fatal(1,"wave sample %0d got %h expected %h",offset+k,got,reference_sample(offset+k));
                end
                expected_offset=offset+count;
                if(expected_offset==512) begin expected_offset=0;expected_capture=expected_capture+1;end
            end else $fatal(1,"unexpected packet type %h",frame[2]);
        end
        $fclose(fixture);
        if(wave_count!=10 || interleaved_status<2 || status_count<4)
            $fatal(1,"status starvation or incomplete wave: status=%0d wave=%0d interleaved=%0d",status_count,wave_count,interleaved_status);
        @(negedge clk);rst_n=0;
        repeat(4) @(negedge clk);
        if(tx!==1 || dut.capture_ready!==0) $fatal(1,"reset left stale UART/capture state");
        $display("PASS: tb_telemetry_wave 1024 exact samples, 10 physical UART wave packets, %0d status packets, %0d interleaved",status_count,interleaved_status);
        $finish;
    end
    initial begin #20000000;$fatal(1,"telemetry waveform timeout");end
endmodule
`default_nettype wire
