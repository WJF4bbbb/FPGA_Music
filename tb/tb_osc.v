// tb_osc -- 只测 osc 一个模块：给它时钟、给采样节拍、看波形、数频率
// Owner: B
// 跑法（在 FPGA_Music 目录下）：
//   iverilog -g2012 -o sim/tb_osc.vvp rtl/osc.v rtl/sin_rom.v tb/tb_osc.v
//   vvp sim/tb_osc.vvp

`timescale 1ns/1ps

module tb_osc;

reg         clk       = 1'b0;
reg         rst_n     = 1'b0;
reg         frame_tick = 1'b0;
reg  [6:0]  note      = 7'd60;
reg  signed [3:0] bend   = 4'sd0;
reg  [1:0]  timbre    = 2'd0;

wire signed [15:0] wave;
wire               valid;

localparam FRAME = 576;     // 每 576 拍一个采样节拍 = 46875Hz

integer cyc        = 0;
integer n_sample   = 0;
integer last_cross = -1;
integer mn         = 32767;
integer mx         = -32768;
reg signed [15:0] prev = 16'sd0;

always #18.5185 clk = ~clk;

osc dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .frame_tick (frame_tick),
    .note      (note),
    .bend      (bend),
    .timbre    (timbre),
    .wave      (wave),
    .valid     (valid)
);

// 产生采样节拍：每 FRAME 拍一下
always @(posedge clk) begin
    cyc       = cyc + 1;
    frame_tick = (cyc % FRAME == 0);
end

// 每出一个新样本就看看：过零了就数周期，顺便记最大最小值
always @(posedge clk) begin
    if (valid) begin
        n_sample = n_sample + 1;

        if (wave > mx) mx = wave;
        if (wave < mn) mn = wave;

        if (prev < 0 && wave >= 0) begin
            if (last_cross >= 0)
                $display("  note %0d : 一个周期 = %0d 个样本  ->  %0d Hz",
                         note, n_sample - last_cross, 46875 / (n_sample - last_cross));
            last_cross = n_sample;
        end
        prev = wave;
    end
end

task run_note;
    input [6:0]  new_note;
    input integer n_samples;
    begin
        note      = new_note;
        mn        = 32767;
        mx        = -32768;
        last_cross = -1;
        repeat (n_samples) @(posedge valid);
        $display("note %0d 幅度范围: %0d .. %0d", new_note, mn, mx);
    end
endtask

initial begin
    $dumpfile("sim/dump_osc.vcd");
    $dumpvars(1, tb_osc);

    #200 rst_n = 1'b1;
    @(posedge valid);

    $display("==== 看前 40 个样本（正弦应该从 0 往上爬）====");
    repeat (40) begin
        @(posedge valid);
        $display("  样本 %0d : wave = %0d", n_sample, wave);
    end

    $display("==== 测频率 ====");
    run_note(7'd60, 1200);   // C4  261.63 Hz
    run_note(7'd64, 1200);   // E4  329.63 Hz
    run_note(7'd72, 1200);   // C5  523.25 Hz

    $display("================================");
    $display("总样本数 = %0d", n_sample);
    $display("================================");
    $finish;
end

endmodule
