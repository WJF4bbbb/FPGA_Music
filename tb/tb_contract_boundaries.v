// This .v testbench uses SystemVerilog; keep IDE keyword parsing consistent with -g2012.
`begin_keywords "1800-2012"
`timescale 1ns/1ps
`default_nettype none
// Focused contract regressions. No audio is injected into the real top.
module tb_contract_boundaries;
    reg clk=0,rst_n=0,ft=0;
    reg [3:0] vv=0;
    reg [63:0] samples=64'd10000;
    wire signed [15:0] sample;
    wire valid;
    wire [31:0] clips,overflow;
    wire signed [15:0] saturated_sample;
    wire saturated_valid;
    wire [31:0] saturated_clips;
    reg [15:0] stress_valid=0;
    reg [255:0] stress_samples={16{16'h7fff}};
    reg [7:0] keys=0;
    wire ev;
    wire [2:0] id;
    wire [6:0] note;
    wire on;
    integer errors=0;
    always #5 clk=~clk;
    mixer mix(.clk(clk),.rst_n(rst_n),.frame_tick(ft),.voice_samples(samples),
              .voice_valid(vv),.master_gain(16'd65535),.sample(sample),.valid(valid),.clip_count(clips));
    note_event ne(.clk(clk),.rst_n(rst_n),.key_state(keys),.evt_ready(1'b0),
                  .evt_valid(ev),.evt_key_id(id),.evt_note(note),.evt_on(on),.overflow_count(overflow));
    // 16 lanes are a statistic stress fixture ONLY (formal system supports 4/8).
    // Legal 4/8-lane headroom makes clipping unreachable at 16-bit gain.
    mixer #(.NVOICE(16)) saturation_fixture(.clk(clk),.rst_n(rst_n),.frame_tick(ft),
        .voice_samples(stress_samples),.voice_valid(stress_valid),.master_gain(16'd65535),
        .sample(saturated_sample),.valid(saturated_valid),.clip_count(saturated_clips));
    task step; begin @(negedge clk);#1;end endtask
    task check(input bit ok,input string message);
        if(!ok) begin $display("FAIL t=%0t: %s",$time,message);errors=errors+1;end
    endtask
    initial begin
        step;step;rst_n=1;
        ft=1;step;ft=0;vv=4'b0001;step;
        check(valid===0,$sformatf("incomplete frame must not emit PCM: valid=%b expected=0",valid));
        vv=4'b1111;step;
        check(valid===1 && sample===16'sd2499,"complete frame keeps original signed sum/headroom/gain arithmetic");
        vv=0;step;check(valid===0,"no frame valid when all lanes invalid");
        repeat(2) begin keys=8'hff;step;keys=0;step;end
        check(ne.cnt===32,"FIFO filled through actual key transitions, ready held low");
        keys=8'hff;step;
        check(overflow!=0,"full FIFO explicitly counts rejected pushes");
        // Statistic-only boundary setup avoids billions of cycles. This is a
        // unit-test deposit at negedge, never an audio/event injection or force.
        ne.overflow_count=32'hfffffffe;
        step;
        check(overflow===32'hffffffff,$sformatf("overflow saturation actual=%h expected=ffffffff",overflow));
        step;check(overflow===32'hffffffff,"saturated statistic stays at maximum");
        saturation_fixture.clip_cnt=32'hfffffffe;
        stress_valid=16'hffff;step;
        check(saturated_sample===16'sd32767 && saturated_clips===32'hffffffff,
              "positive clipping clamps PCM and reaches maximum statistic");
        step;
        check(saturated_clips===32'hffffffff,$sformatf("clip counter saturates actual=%h",saturated_clips));
        stress_samples={16{16'h8000}};step;
        check(saturated_sample===-16'sd32768 && saturated_clips===32'hffffffff,
              "negative clipping clamps PCM and preserves saturated statistic");
        if(errors) $finish_and_return(1);
        $display("PASS: tb_contract_boundaries all checks passed");$finish;
    end
endmodule
`default_nettype wire
`end_keywords
