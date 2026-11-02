`timescale 1ns/1ps
`default_nettype none
module tb_ttp229_reader;
    parameter integer POWERUP_CYCLES=13500000;
    reg clk=0,rst_n=0,chip_rst_n=0;
    reg [15:0] touch=0;
    reg connected=1,noise=0;
    wire scl,model_sdo;
    wire sdo=connected ? (model_sdo ^ noise) : 1'b1;
    wire [15:0] keys_state;
    wire keys_valid,keys_commit;
    ttp229_reader #(.STARTUP_CYCLES(POWERUP_CYCLES)) dut(.*);
    ttp229_model chip(.rst_n(chip_rst_n),.scl(scl),.keys(touch),.sdo(model_sdo));
    always #18.518518518 clk=~clk;
    integer cycle=0,checks=0,commits=0,k,start_cycle,last_edge=0,low_start=0;
    integer frame_edges=0,last_idle_edge=0,last_commit=0,availability=0,latency=0,max_latency=0;
    reg [15:0] previous=0,expected=0;
    reg was_commit=0;
    reg verify_data=1;
    reg probe_scl=1,probe_rst_n=0;
    wire probe_sdo;
    ttp229_model timeout_probe(.rst_n(probe_rst_n),.scl(probe_scl),.keys(16'h0001),.sdo(probe_sdo));
    initial begin
        #100;probe_rst_n=1;#1000;probe_scl=0;#5000;probe_scl=1;
        #1996000;probe_scl=0;#201;
        check(timeout_probe.frame_count==1 && timeout_probe.bit_number==2,
              "1.996 ms since last edge must NOT trigger 2 ms timeout even if active-edge interval exceeds 2 ms");
        #5000;probe_scl=1;#2001000;probe_scl=0;#201;
        check(timeout_probe.frame_count==2 && timeout_probe.bit_number==1,"idle over 2 ms resets peripheral bit index");
    end
    task check(input bit ok,input string message);
        checks=checks+1;
        if(ok!==1'b1) begin $display("FAIL reader cycle=%0d: %s",cycle,message);$finish_and_return(1);end
    endtask
    task cycles(input integer n); repeat(n) @(negedge clk); #1; endtask
    task next_commit;
        integer old;
        begin old=commits; while(commits==old) cycles(1); end
    endtask
    task settled(input [15:0] value);
        begin
            touch=value;availability=cycle;
            // May arrive just after the chip snapshots the current frame.
            next_commit;
            if(keys_state!==value) next_commit;
            check(keys_state===value,$sformatf("16-bit channel map expected=%h actual=%h",value,keys_state));
            latency=cycle-availability;
            if(latency>max_latency) max_latency=latency;
            check(latency<=2*31*135+81000+8,"input through worst polling phase includes two read windows and one gap");
        end
    endtask
    always @(posedge clk) cycle=cycle+1;
    // Check EVERY state/pulse transition, rather than allocating strings on
    // 27 million unchanged startup clocks. The atomicity assertion still
    // catches any output change outside a commit, regardless of clk phase.
    always @(keys_state or keys_commit or negedge rst_n) begin
        #1;
        if(!rst_n) begin previous=0;was_commit=0; end
        else begin
            if(keys_commit && !was_commit) begin
                commits=commits+1;last_commit=cycle;
                check(keys_valid,"a committed frame is marked valid");
                check(frame_edges==16,"exactly sixteen wire clocks before atomic commit");
                if(verify_data) check(keys_state===chip.snapshot,"whole frame equals independently latched module bitmap");
                frame_edges=0;
            end else if(!keys_commit && was_commit)
                check(cycle-last_commit==1,"commit lasts exactly one clk pulse");
            if(keys_state!==previous) check(keys_commit,"no partial frame leaks to consumers");
            previous=keys_state;was_commit=keys_commit;
        end
    end
    always @(negedge scl) if(rst_n) begin
        if(last_edge>0 && frame_edges>0) check(cycle-last_edge==270,"100 kHz SCL period");
        if(frame_edges==0 && last_idle_edge>0) check(cycle-last_idle_edge>54000,"true idle since previous rising edge exceeds typical 2 ms timeout");
        last_edge=cycle;low_start=cycle;frame_edges=frame_edges+1;
    end
    always @(posedge scl) if(rst_n && frame_edges>0) begin
        check(cycle-low_start==135,"5 us low phase; sample after model settling and input synchronization");
        last_idle_edge=cycle;
    end
    initial begin
        cycles(4);chip_rst_n=1;rst_n=1;start_cycle=cycle;
        cycles(POWERUP_CYCLES-1);
        check(scl===1 && !keys_valid && !keys_commit && keys_state===0,"full 0.5 second startup never clocks or reports touch");
        next_commit;
        check(cycle-start_cycle>=POWERUP_CYCLES,"first frame follows configured power-on stable wait (default 0.5s)");
        check(keys_state===0,"idle frame has no false press");
        for(k=0;k<16;k=k+1) begin settled(16'b1<<k);settled(0);end
        settled(16'h000f);settled(16'h1f0f);settled(16'hffff);settled(0);
        // Worst polling phase: change immediately after D0 locks old data.
        @(negedge scl);#201;touch=16'h1109;availability=cycle;
        next_commit;check(keys_state===0,"current snapshot is immutable when module updates mid-frame");
        next_commit;latency=cycle-availability;
        check(keys_state===16'h1109 && latency<=89378,$sformatf("worst-phase next complete frame actual=%0d bound=89378",latency));
        $display("LATENCY reader worst_phase=%0d clocks (%0.6f ms)",latency,latency/27000.0);
        // A short disturbance early in LOW must settle before the sampling window.
        touch=16'h8421;@(negedge scl);#400;noise=1;#50;noise=0;
        next_commit;next_commit;check(keys_state===16'h8421,"early data disturbance outside sampling window is rejected");
        settled(0);
        // One-cycle pulse sampled by metastability stage at clk134 must NOT
        // reach a clk135 bit sample. A single-flop bypass would fail this.
        @(negedge scl);repeat(134) @(negedge clk);noise=1;
        @(negedge clk);noise=0;next_commit;
        check(keys_state===0,"SDO sample uses two-stage synchronized history, not first flop");
        // Pulse reaches the pin just before clk135; direct raw-pin sampling
        // would see a false press, while the specified synchronizer cannot.
        @(negedge scl);repeat(135) @(negedge clk);noise=1;
        @(negedge clk);noise=0;next_commit;
        check(keys_state===0,"SDO sample never bypasses synchronization to the raw pin");
        settled(16'h8421);
        // No CRC/ACK exists: an interrupted data wire is not detectable. Require
        // subsequent clean complete frames to restore the correct state.
        verify_data=0;@(negedge scl);connected=0;cycles(700);connected=1;
        next_commit;next_commit;verify_data=1;
        check(keys_state===touch,"clean frame recovers after interrupted data wire without a stuck gate");
        // Reset only FPGA during a partial chip frame; chip does not reset.
        @(negedge scl);cycles(20);rst_n=0;frame_edges=0;last_edge=0;cycles(4);
        check(scl===1 && !keys_valid && keys_state===0,"mid-frame reset discards incomplete data and returns idle");
        rst_n=1;start_cycle=cycle;next_commit;
        check(cycle-start_cycle>=POWERUP_CYCLES && keys_state===touch,"startup gap resynchronizes chip after interrupted frame");
        $display("PASS: tb_ttp229_reader all checks passed; assertions=%0d commits=%0d max_acquisition=%0d",checks,commits,max_latency);
        $finish;
    end
    initial begin #1400000000;$display("FAIL reader: timeout");$finish_and_return(1);end
endmodule
`default_nettype wire
