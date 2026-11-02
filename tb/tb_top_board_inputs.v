`timescale 1ns/1ps
`default_nettype none
// Fast logical boundary test. Serial pins, not final bitmap injection.
module tb_top_board_inputs;
    reg clk=0,rst_n=0,test_enable=0;
    reg [15:0] touch=0;
    wire ttp_scl,ttp_sdo,bclk,lrclk,i2s_data,pa_en;
    wire uart_rx_pin=1'b1;   // 串口空闲高，蓝牙不接管
    wire uart_tx_pin;
    top #(.TTP_STARTUP_CYCLES(20),.TTP_SCL_HALF_CYCLES(10),
          .TTP_FRAME_GAP_CYCLES(300),.TOUCH_CTRL_FILT(4)) dut(.*);
    ttp229_model #(.DATA_DELAY_NS(20),.TIMEOUT_NS(2000)) chip(
        .rst_n(rst_n),.scl(ttp_scl),.keys(touch),.sdo(ttp_sdo));
    defparam dut.u_sensor_frontend.FILT_CYCLES=4;
    always #5 clk=~clk;
    task cycles(input integer n);repeat(n) @(negedge clk);#1;endtask
    task check(input bit ok,input string message);
        if(ok!==1'b1) begin $display("FAIL board inputs: %s",message);$finish_and_return(1);end
    endtask
    task set_touch(input [15:0] value);touch=value;cycles(1300);endtask
    integer k;
    initial begin
        cycles(4);rst_n=1;cycles(1300);
        check(dut.timbre===0 && dut.master_gain===16384 && dut.bend===0,"idle serialized panel does not act");
        check(dut.key_state===0 && dut.voice_gate===0,"idle normalized note bitmap is zero");
        set_touch(16'h0100);check(dut.timbre===1,"TP8 changes timbre");
        cycles(1300);check(dut.timbre===1,"held timbre does not repeat");
        set_touch(0);check(dut.timbre===1,"release does not change timbre");
        set_touch(16'h0200);check(dut.master_gain===20480,"TP9 increases volume");
        cycles(1300);check(dut.master_gain===20480,"held volume does not repeat");
        set_touch(0);set_touch(16'h0400);check(dut.master_gain===16384,"TP10 decreases volume");
        set_touch(0);set_touch(16'h0800);check(dut.bend===4'sd2,"TP11 positive bend");
        set_touch(16'h1800);check(dut.bend===0,"both bend keys cancel");
        set_touch(16'h1000);check(dut.bend===-4'sd2,"TP12 negative bend");
        set_touch(0);check(dut.bend===0,"released bend is zero");
        for(k=0;k<8;k=k+1) begin
            set_touch(16'b1<<k);check(dut.key_state===(8'b1<<k),"TP0..TP7 map to eight notes");
            set_touch(0);check(dut.key_state===0,"all note releases accepted");
        end
        set_touch(16'h000f);check(dut.voice_gate===4'b1111,"four simultaneous touch notes allocate four voices");
        set_touch(16'h020f);check(dut.voice_gate===4'b1111 && dut.master_gain===20480,"notes plus control coexist");
        set_touch(0);set_touch(16'he000);
        check(dut.key_state===0 && dut.normalized_panel===0 && dut.timbre===1 && dut.master_gain===20480,
              "TP13..TP15 remain reserved and do not act");
        test_enable=1;cycles(8);check(dut.test_mode_latched===0,"live mode input ignored");
        rst_n=0;touch=0;cycles(4);rst_n=1;cycles(1300);
        check(dut.test_mode_latched===1,"demo selected only after reset");
        $display("PASS: tb_top_board_inputs all checks passed; 16 serial channels, notes/control/reserved");$finish;
    end
    initial begin #2000000;$display("FAIL board inputs: timeout");$finish_and_return(1);end
endmodule
`default_nettype wire
