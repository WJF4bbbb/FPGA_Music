`timescale 1ns/1ps
`default_nettype none
module tb_test_mode;
    reg clk=0,rst_n=0,enable=0,evt_ready=0;
    wire evt_valid,evt_on;
    wire [2:0] evt_key_id;
    wire [6:0] evt_note;
    localparam integer HOLD_CLOCKS=2*576, RELEASE_CLOCKS=576;
    test_mode #(.HOLD_FRAMES(2),.RELEASE_FRAMES(1)) dut (
        .clk(clk),.rst_n(rst_n),.enable(enable),.evt_ready(evt_ready),
        .evt_valid(evt_valid),.evt_key_id(evt_key_id),.evt_note(evt_note),.evt_on(evt_on)
    );
    always #18.519 clk=~clk;
    integer cycle=0,events=0,total_events=0,rounds=0,last_on=0,last_off=0;
    integer k,sequence_index=0;
    reg [3:0] active=0;
    reg stalled=0;
    reg [10:0] stalled_event;
    reg [15:0] random_state=16'hac35;
    reg random_ready=0;
    function [6:0] note_for;
        input [2:0] key_id;
        begin
            case(key_id)
                0:note_for=60;1:note_for=64;2:note_for=67;3:note_for=72;
                default:note_for=0;
            endcase
        end
    endfunction
    task check;
        input ok;
        input [639:0] message;
        begin
            if(ok !== 1'b1) begin
                $display("FAIL cycle=%0d event=%0d: %0s",cycle,events,message);
                $finish_and_return(1); // Icarus extension, testbench only.
            end
        end
    endtask
    always @(negedge clk) begin
        if(random_ready) begin
            random_state={random_state[14:0],random_state[15]^random_state[13]^random_state[12]^random_state[10]};
            evt_ready=random_state[0] | random_state[2];
        end
    end
    always @(posedge clk) begin
        cycle=cycle+1;
        if(!rst_n) begin
            events=0;sequence_index=0;active=0;stalled=0;last_on=0;last_off=0;
        end else begin
            check((^{evt_valid,evt_key_id,evt_note,evt_on}) !== 1'bx,"known output values");
            if(!enable) check(evt_valid===0,"disabled source emits no event");
            if(stalled) begin
                check(evt_valid===1,"backpressure keeps valid");
                check({evt_key_id,evt_note,evt_on}===stalled_event,"backpressure keeps entire payload");
            end
            stalled=evt_valid && !evt_ready;
            if(stalled) stalled_event={evt_key_id,evt_note,evt_on};
            // Check the first VALID edge, independent of downstream readiness.
            if(evt_valid && evt_on && evt_key_id==0 && sequence_index==0 && last_off!=0)
                check(cycle-last_off>=RELEASE_CLOCKS+1,"release interval cannot be shortened");
            if(evt_valid && !evt_on && evt_key_id==0 && sequence_index==4)
                check(cycle-last_on>=HOLD_CLOCKS+1,"hold interval cannot be shortened");
            if(evt_valid && evt_ready) begin
                check(evt_key_id=== (sequence_index%4),"deterministic key order");
                check(evt_note===note_for(evt_key_id),"MIDI note mapping");
                check(evt_on === (sequence_index<4),"note on/off order");
                if(evt_on) begin
                    check(!active[evt_key_id],"no duplicate note on");active[evt_key_id]=1;
                    if(evt_key_id==3) begin check(active==4'b1111,"four simultaneously held keys");last_on=cycle;end
                end else begin
                    check(active[evt_key_id],"note off matches active key");active[evt_key_id]=0;
                    if(evt_key_id==3) begin
                        check(active==0,"all keys released before next round");last_off=cycle;rounds=rounds+1;
                    end
                end
                $display("event cycle=%0d key=%0d note=%0d on=%0d",cycle,evt_key_id,evt_note,evt_on);
                sequence_index=(sequence_index+1)%8;events=events+1;total_events=total_events+1;
            end
        end
    end
    task reset_source;
        begin
            random_ready=0;
            @(negedge clk);#2 rst_n=0;enable=0;evt_ready=0;
            #1;check({evt_valid,evt_key_id,evt_note,evt_on}===12'b0,"asynchronous reset clears all event outputs");
            repeat(3) @(negedge clk);
            #2 rst_n=1;
        end
    endtask
    task start_source;
        begin @(negedge clk);enable=1;evt_ready=1;end
    endtask
    task wait_events;
        input integer target;
        begin
            while(events<target) begin @(posedge clk);#2;end
        end
    endtask
    initial begin
        $dumpfile("sim/test_mode.vcd");$dumpvars(0,tb_test_mode);
        reset_source;
        repeat(15) begin @(posedge clk);#2;check(evt_valid==0,"idle without enable");end
        start_source;
        wait_events(4);
        repeat(HOLD_CLOCKS) begin @(posedge clk);#2;end
        check(evt_valid && !evt_on && evt_key_id==0,"exact hold length to first off valid");
        wait_events(8);
        repeat(RELEASE_CLOCKS) begin @(posedge clk);#2;end
        check(evt_valid && evt_on && evt_key_id==0,"exact release length to next on valid");
        wait_events(16);
        // Deterministic long stalls before first on, middle on and first off.
        reset_source;
        @(negedge clk);enable=1;
        repeat(23) @(negedge clk);
        check(evt_valid && evt_key_id==0,"first on retained under stall");
        evt_ready=1;wait_events(2);
        @(negedge clk);evt_ready=0;
        repeat(37) @(negedge clk);
        check(events==2,"stalled on not consumed");
        evt_ready=1;wait_events(4);
        @(negedge clk);evt_ready=0;
        repeat(HOLD_CLOCKS+40) @(negedge clk);
        check(evt_valid && !evt_on && events==4,"off retained under stall");
        random_ready=1;wait_events(24);
        // Mode changes are reset-only: reset both source and downstream state.
        for(k=1;k<=4;k=k+1) begin
            reset_source;start_source;wait_events(k);reset_source;
            repeat(8) @(negedge clk);
            check(evt_valid==0 && events==0,"reset after partial chord leaves source idle");
        end
        reset_source;start_source;wait_events(6);reset_source;
        start_source;wait_events(8);
        // Reset while a pending event is backpressured.
        reset_source;@(negedge clk);enable=1;
        repeat(12) @(negedge clk);
        check(evt_valid && !evt_ready,"pending before reset");reset_source;
        start_source;wait_events(8);
        $display("PASS: test_mode, %0d checked handshakes, %0d complete rounds, stalls and reset restarts",total_events,rounds);
        $finish;
    end
    initial begin #2000000;$display("FAIL: timeout");$finish_and_return(1);end
endmodule
`default_nettype wire
