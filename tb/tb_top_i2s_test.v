
`timescale 1ns/1ps
`default_nettype none

module tb_top_i2s_test;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    wire i2s_bclk;
    wire i2s_lrclk;
    wire i2s_data;

    // 27 MHz system clock
    always #18.5185185 clk = ~clk;

    top_i2s_test dut (
        .clk(clk),
        .rst_n(rst_n),
        .i2s_bclk(i2s_bclk),
        .i2s_lrclk(i2s_lrclk),
        .i2s_data(i2s_data)
    );

    integer frames = 0;
    integer bits = 0;
    integer total_frames = 0;

    reg [15:0] left_sample = 16'd0;
    reg [15:0] right_sample = 16'd0;
    reg [15:0] rx_word = 16'd0;
    reg [15:0] expected_sample;
    reg prev_ws = 1'b1;
    reg start_next = 1'b0;
    reg rx_active = 1'b0;
    reg rx_channel = 1'b0;
    reg left_valid = 1'b0;

    task check;
        input ok;
        input [639:0] message;
        begin
            if (ok !== 1'b1)
                $fatal(1, "FAIL: top_i2s_test frame %0d: %0s", frames, message);
        end
    endtask

    // Use only the external pins to decode Philips I2S. The rising edge
    // observing a WS change still carries the PREVIOUS channel's LSB.
    // The NEXT rising edge carries the new channel's MSB. At startup, wait
    // for a WS transition instead of treating the first BCLK as a left MSB.
    always @(posedge i2s_bclk or negedge rst_n) begin
        if (!rst_n) begin
            frames = 0;
            bits = 0;
            prev_ws = 1'b1;
            start_next = 1'b0;
            rx_active = 1'b0;
            rx_channel = 1'b0;
            left_valid = 1'b0;
            rx_word = 16'd0;
            left_sample = 16'd0;
            right_sample = 16'd0;
        end else begin
            check((^{i2s_lrclk, i2s_data}) !== 1'bx, "known WS/data on BCLK rise");
            if (start_next) begin
                rx_channel = prev_ws;
                rx_word = 16'd0;
                bits = 0;
                rx_active = 1'b1;
                start_next = 1'b0;
            end

            if (rx_active) begin
                rx_word = {rx_word[14:0], i2s_data};
                bits = bits + 1;
                if (bits == 16) begin
                    rx_active = 1'b0;
                    if (!rx_channel) begin
                        left_sample = rx_word;
                        left_valid = 1'b1;
                    end else begin
                        right_sample = rx_word;
                        check(left_valid, "right channel follows a complete left channel");
                        left_valid = 1'b0;
                        frames = frames + 1;
                        check(left_sample === right_sample, "left and right PCM match");

                        // First load is silent. The first tick produces E000
                        // for the second frame; then 2000/E000 alternate.
                        if (frames == 1)
                            expected_sample = 16'h0000;
                        else if (frames % 2 == 0)
                            expected_sample = 16'he000;
                        else
                            expected_sample = 16'h2000;
                        if (left_sample !== expected_sample)
                            $fatal(1, "FAIL: frame %0d, expected %h, L=%h R=%h",
                                   frames, expected_sample, left_sample, right_sample);
                        check(dut.underrun_count === 32'd0, "continuous stream has no underruns");
                        total_frames = total_frames + 1;
                    end
                end
            end

            if (i2s_lrclk != prev_ws) begin
                check(!rx_active, "WS transition coincides with previous channel LSB");
                start_next = 1'b1;
                prev_ws = i2s_lrclk;
            end
        end
    end

    initial begin
        $dumpfile("sim/tb_top_i2s_test.vcd");
        $dumpvars(0, tb_top_i2s_test);

        repeat (20) @(posedge clk);
        // Release reset away from the DUT sampling edge to avoid a race.
        @(negedge clk);
        rst_n = 1'b1;

        wait (frames >= 100);
        // Reset during a word and verify the receiver and sample pipeline
        // both restart, including the initial silent frame.
        repeat (7) @(negedge i2s_bclk);
        #2 rst_n = 1'b0;
        #1;
        check({i2s_bclk, i2s_lrclk, i2s_data} === 3'b010, "asynchronous output reset");
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        wait (frames >= 100);
        // Let the receiver finish all assertions before reporting success.
        @(negedge clk);
        check(total_frames == 200, "100 complete stereo frames before and after reset");
        $display("PASS: top_i2s_test, %0d stereo frames; startup, alternating PCM, no underruns and reset", total_frames);
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1, "FAIL: top_i2s_test simulation timeout");
    end

endmodule

`default_nettype wire
