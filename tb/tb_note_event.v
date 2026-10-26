`timescale 1ns/1ps
module tb_note_event;
    reg clk, rst_n;
    reg [7:0] key_state;
    reg evt_ready;
    wire evt_valid;
    wire [2:0] evt_key_id;
    wire [6:0] evt_note;
    wire evt_on;
    wire [31:0] overflow_count;

    note_event dut (
        .clk(clk), .rst_n(rst_n), .key_state(key_state), .evt_ready(evt_ready),
        .evt_valid(evt_valid), .evt_key_id(evt_key_id), .evt_note(evt_note),
        .evt_on(evt_on), .overflow_count(overflow_count)
    );

    always #10 clk = ~clk;
    task wait_cycles; input integer n; integer j; begin for (j=0;j<n;j=j+1) @(posedge clk); end endtask

    // pop one event, returning its fields; guarded against hangs
    task pop_event; output [2:0] id; output [6:0] note; output on;
        integer guard;
        begin
            guard = 0;
            while (!evt_valid) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 2000) begin $display("FAIL pop timeout"); $finish; end
            end
            id = evt_key_id; note = evt_note; on = evt_on;
            evt_ready = 1'b1; @(posedge clk);
            evt_ready = 1'b0; @(posedge clk);
        end
    endtask

    integer pass;
    reg [2:0] rid; reg [6:0] rnote; reg ron;
    initial begin
        $dumpfile("sim/tb_note_event.vcd");
        $dumpvars(0, tb_note_event);
        pass = 1;
        clk = 0; rst_n = 0; key_state = 8'd0; evt_ready = 1'b0;
        wait_cycles(2); rst_n = 1; wait_cycles(2);

        // T1: keys held at reset release => one press each, ascending key_id
        key_state = 8'b00100010;   // key1 (62), key5 (69)
        wait_cycles(2);
        pop_event(rid, rnote, ron);
        if (!(rid==3'd1 && rnote==7'd62 && ron==1'b1)) begin $display("FAIL T1a id=%0d note=%0d on=%b", rid, rnote, ron); pass=0; end
        pop_event(rid, rnote, ron);
        if (!(rid==3'd5 && rnote==7'd69 && ron==1'b1)) begin $display("FAIL T1b id=%0d note=%0d on=%b", rid, rnote, ron); pass=0; end
        if (evt_valid) begin $display("FAIL T1 extra events left"); pass=0; end

        // T2: single press then release
        key_state = 8'b00100011;   // add key0 (60) press
        wait_cycles(2);
        pop_event(rid, rnote, ron);
        if (!(rid==3'd0 && rnote==7'd60 && ron==1'b1)) begin $display("FAIL T2 press id=%0d", rid); pass=0; end
        key_state = 8'b00100010;   // release key0
        wait_cycles(2);
        pop_event(rid, rnote, ron);
        if (!(rid==3'd0 && rnote==7'd60 && ron==1'b0)) begin $display("FAIL T2 release id=%0d on=%b", rid, ron); pass=0; end

        // T3: simultaneous release + presses -> releases first, then sorted presses
        // currently held: key1, key5. change: release key1, press key3(65), key7(72)
        key_state = 8'b10101000;
        wait_cycles(2);
        pop_event(rid, rnote, ron);
        if (!(rid==3'd1 && rnote==7'd62 && ron==1'b0)) begin $display("FAIL T3 rel id=%0d on=%b", rid, ron); pass=0; end
        pop_event(rid, rnote, ron);
        if (!(rid==3'd3 && rnote==7'd65 && ron==1'b1)) begin $display("FAIL T3 press1 id=%0d", rid); pass=0; end
        pop_event(rid, rnote, ron);
        if (!(rid==3'd7 && rnote==7'd72 && ron==1'b1)) begin $display("FAIL T3 press2 id=%0d", rid); pass=0; end

        // T4: backpressure - with ready=0 the event must be held, not lost
        key_state = 8'b10101100;   // add key2 (64) press, keep key3/5/7
        wait_cycles(2);
        if (!evt_valid) begin $display("FAIL T4 no valid"); pass=0; end
        repeat (6) @(posedge clk);
        if (!(evt_valid && evt_key_id==3'd2 && evt_note==7'd64 && evt_on==1'b1))
            begin $display("FAIL T4 fields not held id=%0d note=%0d on=%b", evt_key_id, evt_note, evt_on); pass=0; end
        evt_ready = 1'b1; @(posedge clk); evt_ready = 1'b0; @(posedge clk);
        if (evt_valid) begin $display("FAIL T4 still valid after pop"); pass=0; end

        // T5: overflow counting - stress the FIFO without popping
        evt_ready = 1'b0;
        repeat (10) begin
            key_state = 8'b11111111; wait_cycles(1);
            key_state = 8'b00000000; wait_cycles(1);
        end
        if (overflow_count == 32'd0) begin $display("FAIL T5 overflow not counted"); pass=0; end
        // drain leftovers to clean up
        evt_ready = 1'b1;
        while (evt_valid) @(posedge clk);
        evt_ready = 1'b0;

        if (pass) begin
            $display("PASS: tb_note_event all checks passed");
            $finish;
        end else begin
            $display("FAIL: tb_note_event");
            $finish;
        end
    end
endmodule
