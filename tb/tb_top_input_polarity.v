`timescale 1ns/1ps
`default_nettype none
// Replaces obsolete parallel-mask tests with both BSF wire polarities.
module tb_top_input_polarity;
    reg clk=0,rst_n=0;
    reg [7:0] logical_notes=0;
    reg [4:0] logical_panel=0;
    wire [15:0] touch={3'd0,logical_panel[2],logical_panel[3],logical_panel[0],logical_panel[1],logical_panel[4],logical_notes};
    integer n;
    always #5 clk=~clk;
    task cycles(input integer count);repeat(count) @(negedge clk);#1;endtask
    genvar g;
    generate for(g=0;g<2;g=g+1) begin: configurations
        wire ttp_scl,ttp_sdo,bclk,lrclk,i2s_data,pa_en;
        top #(.TTP_ACTIVE_LOW(g),.TTP_STARTUP_CYCLES(20),.TTP_SCL_HALF_CYCLES(10),
              .TTP_FRAME_GAP_CYCLES(300),.TOUCH_CTRL_FILT(4)) dut(
            .clk(clk),.rst_n(rst_n),.ttp_scl(ttp_scl),.ttp_sdo(ttp_sdo),.test_enable(1'b0),
            .bclk(bclk),.lrclk(lrclk),.i2s_data(i2s_data),.pa_en(pa_en));
        ttp229_model #(.ACTIVE_LOW(g),.DATA_DELAY_NS(20),.TIMEOUT_NS(2000)) chip(
            .rst_n(rst_n),.scl(ttp_scl),.keys(touch),.sdo(ttp_sdo));
        defparam dut.u_sensor_frontend.FILT_CYCLES=4;
        task check_settled;
            reg signed [3:0] expected_bend;
            begin
                expected_bend=logical_panel[3] && !logical_panel[2] ? 4'sd2 :
                              logical_panel[2] && !logical_panel[3] ? -4'sd2 : 4'sd0;
                if(dut.key_state!==logical_notes || dut.u_control_panel.db!==logical_panel ||
                   dut.normalized_panel!==logical_panel || dut.bend!==expected_bend) begin
                    $display("FAIL polarity: wire active_low=%0d notes=%h/%h panel=%b/%b bend=%0d/%0d",
                             g,dut.key_state,logical_notes,dut.u_control_panel.db,logical_panel,dut.bend,expected_bend);
                    $finish_and_return(1);
                end
            end
        endtask
    end endgenerate
    task check_all;configurations[0].check_settled;configurations[1].check_settled;endtask
    initial begin
        cycles(4);rst_n=1;cycles(1300);check_all;
        for(n=0;n<256;n=n+1) begin logical_notes=n;cycles(1300);check_all;end
        logical_notes=0;
        for(n=0;n<32;n=n+1) begin logical_panel=n;cycles(1300);check_all;end
        $display("PASS: tb_top_input_polarity all checks passed; two wire polarities, 256 note patterns, 32 panel patterns");$finish;
    end
    initial begin #5000000;$display("FAIL polarity: timeout");$finish_and_return(1);end
endmodule
`default_nettype wire
