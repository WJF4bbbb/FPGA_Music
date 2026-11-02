// Compare a separately synthesized osc (module renamed osc_gowin) with RTL.
// Use Gowin's official gw2a/prim_sim.v; no replacement primitive models.
`timescale 1ns/1ps
`default_nettype none
module tb_osc_gowin_compare;
    reg clk=0, rst_n=0, frame_tick=0;
    reg [6:0] note=60;
    reg signed [3:0] bend=0;
    reg [1:0] timbre=0;
    wire signed [15:0] rtl_wave, mapped_wave;
    wire rtl_valid, mapped_valid;
    reg [31:0] expected_phase;
    reg [31:0] previous_phase;
    reg [31:0] step;
    integer t,b,k,g,samples=0,checks=0;
    always #5 clk=~clk;
    osc reference (.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
        .note(note),.bend(bend),.timbre(timbre),.wave(rtl_wave),.valid(rtl_valid));
    osc_gowin mapped (.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
        .note(note),.bend(bend),.timbre(timbre),.wave(mapped_wave),.valid(mapped_valid));

    task cycle;
        input enable;
        begin
            // Call on falling edges: inputs settle before the next rising edge.
            frame_tick=enable;
            #1;
            previous_phase=reference.phase;
            step=reference.fcw_bent;
            expected_phase=enable ? previous_phase+step : previous_phase;
            @(posedge clk); #1;
            if(rst_n && reference.phase !== expected_phase)
                $fatal(1,"FAIL phase continuity timbre=%0d bend=%0d",timbre,bend);
            if(rtl_valid !== mapped_valid)
                $fatal(1,"FAIL mapped valid timbre=%0d bend=%0d",timbre,bend);
            if(rtl_valid) begin
                if(rtl_wave !== mapped_wave)
                    $fatal(1,"FAIL mapped sample t=%0d b=%0d phase=%h RTL=%0d mapped=%0d",
                        timbre,bend,previous_phase,rtl_wave,mapped_wave);
                samples=samples+1;
            end
            checks=checks+1;
            @(negedge clk);
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);
        rst_n=1;
        for(t=0;t<4;t=t+1) begin
            for(b=-2;b<=2;b=b+1) begin
                timbre=t;
                bend=b;
                for(k=0;k<512;k=k+1) begin
                    // Exercise consecutive ticks, gaps, and control changes
                    // without reset. Each note remains within the RTL table.
                    note=60+(k%13);
                    cycle(1);
                    for(g=0;g<(k%4);g=g+1) cycle(0);
                end
                $display("PASS mapped osc timbre=%0d bend=%0d: 512 exact valid samples",t,b);
            end
        end
        // Also cover the formal 576-clock audio interval.
        for(k=0;k<8;k=k+1) begin
            timbre=k%4; bend=(k%5)-2;
            cycle(1);
            repeat(575) cycle(0);
        end
        $display("PASS: osc Gowin comparison samples=%0d cycles=%0d; dynamic timbre/bend, phase hold/advance",samples,checks);
        $finish;
    end
    initial begin #10000000; $fatal(1,"FAIL mapped osc watchdog"); end
endmodule
`default_nettype wire
