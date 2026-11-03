`timescale 1ns/1ps

module tb_learning_answer_input;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg answer_page_active = 1'b0;
    reg cycle_pulse = 1'b0;
    reg [3:0] switch_async = 4'b0000;
    wire [1:0] selected_answer;
    wire switch_selection_active;
    wire selection_valid;

    always #5 clk = ~clk;

    learning_answer_input dut (
        .clk(clk),
        .rst(rst),
        .answer_page_active(answer_page_active),
        .cycle_pulse(cycle_pulse),
        .switch_async(switch_async),
        .selected_answer(selected_answer),
        .switch_selection_active(switch_selection_active),
        .selection_valid(selection_valid)
    );

    task automatic pulse_cycle;
        begin
            @(negedge clk); cycle_pulse = 1'b1;
            @(negedge clk); cycle_pulse = 1'b0;
            #1;
        end
    endtask

    task automatic wait_switch_sync;
        begin
            repeat (3) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        @(negedge clk); answer_page_active = 1'b1;

        pulse_cycle();
        if (selected_answer != 2'd1 || switch_selection_active || !selection_valid)
            $fatal(1, "KEY2 did not select B in normal mode");

        pulse_cycle();
        pulse_cycle();
        pulse_cycle();
        if (selected_answer != 2'd0)
            $fatal(2, "key selection did not wrap D to A");

        // Exactly one of SW1/SW2/SW3/SW4 directly selects A/B/C/D.
        switch_async = 4'b0001;
        wait_switch_sync();
        if (!switch_selection_active || !selection_valid || selected_answer != 2'd0)
            $fatal(3, "SW1 did not directly select A");

        switch_async = 4'b0010;
        wait_switch_sync();
        if (!selection_valid || selected_answer != 2'd1)
            $fatal(4, "SW2 did not directly select B");

        pulse_cycle();
        if (selected_answer != 2'd1)
            $fatal(5, "KEY2 changed direct switch selection");

        switch_async = 4'b0100;
        wait_switch_sync();
        if (!selection_valid || selected_answer != 2'd2)
            $fatal(6, "SW3 did not directly select C");

        switch_async = 4'b1000;
        wait_switch_sync();
        if (!selection_valid || selected_answer != 2'd3)
            $fatal(7, "SW4 did not directly select D");

        switch_async = 4'b0011;
        wait_switch_sync();
        if (!switch_selection_active || selection_valid)
            $fatal(8, "multiple raised switches were not rejected");

        switch_async = 4'b0000;
        wait_switch_sync();
        if (switch_selection_active || !selection_valid || selected_answer != 2'd0)
            $fatal(9, "leaving switch selection did not return to A");

        pulse_cycle();
        if (selected_answer != 2'd1)
            $fatal(10, "normal KEY2 selection did not recover");

        @(negedge clk); answer_page_active = 1'b0;
        @(posedge clk); #1;
        if (selected_answer != 2'd0)
            $fatal(11, "leaving answer page did not clear selection");

        $display("TEST_PASS tb_learning_answer_input");
        $finish;
    end
endmodule
