`timescale 1ns/1ps
`default_nettype none
module tb_audio_timing;
    reg clk = 0;
    reg rst_n = 1;
    wire bclk, lrclk, bclk_rise_ce, bclk_fall_ce;
    wire [4:0] bit_index;
    wire frame_load, frame_tick;
    integer cycle, edge_no, expected_index, frames, total_frames = 0;
    integer last_edge, last_rise, last_fall, last_ws, last_ws_up, last_ws_down;
    integer last_frame, slots, left_slots, right_slots, ws_boundary;
    reg old_bclk, old_lrclk, rise_ce, fall_ce, load_ce;
    reg [4:0] old_index;
    reg expected_ws;
    audio_timing dut (
        .clk(clk), .rst_n(rst_n), .bclk(bclk), .lrclk(lrclk),
        .bclk_rise_ce(bclk_rise_ce), .bclk_fall_ce(bclk_fall_ce),
        .bit_index(bit_index), .frame_load(frame_load), .frame_tick(frame_tick)
    );
    always #18.519 clk = ~clk;

    task check;
        input condition;
        input [639:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL cycle=%0d: %0s", cycle, message);
                // Icarus extension: terminate with nonzero process status.
                $finish_and_return(1);
            end
        end
    endtask

    task reset_check;
        begin
            // Assert away from a clock edge, including during active operation.
            @(negedge clk); #3 rst_n = 0;
            #1;
            check({bclk,lrclk,bit_index} === {1'b0,1'b1,5'd31}, "asynchronous reset state");
            check({bclk_rise_ce,bclk_fall_ce,frame_load,frame_tick} === 4'b0, "reset masks enables");
            repeat (3) @(negedge clk);
            #3 rst_n = 1;
            cycle=0; frames=0; last_edge=0; last_rise=0; last_fall=0;
            last_ws=0; last_ws_up=0; last_ws_down=0; last_frame=0;
            slots=0; left_slots=0; right_slots=0; ws_boundary=0;
        end
    endtask

    task run_cycles;
        input integer count;
        integer k;
        begin
            for (k=0; k<count; k=k+1) begin
                @(posedge clk);
                cycle=cycle+1;
                // Capture enables/index BEFORE nonblocking register updates.
                old_bclk=bclk; old_lrclk=lrclk; old_index=bit_index;
                rise_ce=bclk_rise_ce; fall_ce=bclk_fall_ce; load_ce=frame_load;
                check((^{bclk,lrclk,bit_index,bclk_rise_ce,bclk_fall_ce,frame_load,frame_tick}) !== 1'bx, "no X/Z");
                check(rise_ce === ((cycle%18)==9), "rise enable/startup/one-cycle width");
                check(fall_ce === ((cycle%18)==0), "fall enable/startup/one-cycle width");
                check(!(rise_ce && fall_ce), "mutually exclusive enables");
                edge_no=cycle/18;
                expected_index=(31+((cycle-1)/18))%32;
                check(old_index === expected_index[4:0], "pre-edge index sequence");
                check(load_ce === (fall_ce && old_index==31), "frame load boundary");
                check(frame_tick === load_ce, "frame tick equals load");
                #1;
                check(bclk === (((cycle/9)%2)!=0), "BCLK actual edge matches enable");
                check((bclk != old_bclk) === (rise_ce || fall_ce), "no delayed/extra BCLK edge");
                check(bit_index === ((31+edge_no)%32), "index increments only on falling enable");
                expected_ws=old_lrclk;
                if (fall_ce && old_index==15) expected_ws=1;
                if (fall_ce && old_index==31) expected_ws=0;
                check(lrclk === expected_ws, "LRCLK changes at old index 15/31 only");
                if (rise_ce || fall_ce) begin
                    if(last_edge!=0) check(cycle-last_edge==9, "BCLK half period");
                    last_edge=cycle;
                end
                if (rise_ce) begin
                    if(last_rise!=0) check(cycle-last_rise==18, "rise-to-rise period");
                    last_rise=cycle;
                end
                if (fall_ce) begin
                    if(last_fall!=0) check(cycle-last_fall==18, "fall-to-fall period");
                    last_fall=cycle;
                    if(old_index==0 || old_index==16)
                        check(cycle-ws_boundary==18, "WS leads next MSB by one BCLK");
                    if(last_frame!=0) begin
                        slots=slots+1;
                        if(old_index<16) left_slots=left_slots+1;
                        else right_slots=right_slots+1;
                    end
                end
                if(lrclk != old_lrclk) begin
                    if(last_ws!=0) check(cycle-last_ws==288, "WS half period");
                    last_ws=cycle; ws_boundary=cycle;
                    if(lrclk) begin
                        if(last_ws_up!=0) check(cycle-last_ws_up==576, "WS rising period");
                        last_ws_up=cycle;
                    end else begin
                        if(last_ws_down!=0) check(cycle-last_ws_down==576, "WS falling period");
                        last_ws_down=cycle;
                    end
                end
                if(load_ce) begin
                    if(last_frame!=0) begin
                        check(cycle-last_frame==576, "frame period");
                        check(slots==32 && left_slots==16 && right_slots==16, "32 slots, 16 per channel");
                        frames=frames+1; total_frames=total_frames+1;
                    end
                    last_frame=cycle; slots=0; left_slots=0; right_slots=0;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_audio_timing.vcd");
        $dumpvars(0,tb_audio_timing);
        reset_check;
        run_cycles(576*101+18);
        check(frames>=100, "at least 100 complete steady frames");
        run_cycles(4); // Reset in the middle of a BCLK half period.
        reset_check;
        run_cycles(18+18*11+3); // Reset in the middle of a frame.
        reset_check;
        run_cycles(576*2+18);
        check(frames==2, "deterministic restart after mid-frame reset");
        $display("PASS: audio_timing, %0d complete frames, startup and two running resets",total_frames);
        $finish;
    end
    initial begin
        #5000000;
        $display("FAIL: simulation timeout");
        $finish_and_return(1);
    end
endmodule
`default_nettype wire
