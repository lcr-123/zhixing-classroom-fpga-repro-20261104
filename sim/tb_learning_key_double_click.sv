`timescale 1ns/1ps

module tb_learning_key_double_click;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg active = 1'b0;
    reg [3:0] context_id = 4'd3;
    reg short_pulse = 1'b0;
    reg long_pulse = 1'b0;
    wire single_pulse;
    wire double_pulse;
    integer single_count = 0;
    integer double_count = 0;

    always #5 clk = ~clk;

    learning_key_double_click #(
        .WINDOW_CYCLES(8),
        .COUNTER_WIDTH(4)
    ) dut (
        .clk(clk), .rst(rst), .active(active), .context_id(context_id),
        .short_pulse(short_pulse), .long_pulse(long_pulse),
        .single_pulse(single_pulse), .double_pulse(double_pulse)
    );

    always @(posedge clk) begin
        if (single_pulse)
            single_count <= single_count + 1;
        if (double_pulse)
            double_count <= double_count + 1;
    end

    task automatic click;
        begin
            @(negedge clk);
            short_pulse = 1'b1;
            @(negedge clk);
            short_pulse = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        active = 1'b1;

        click();
        repeat (3) @(negedge clk);
        if (single_count != 0 || double_count != 0)
            $fatal(1, "first click escaped before double-click window");
        click();
        repeat (2) @(negedge clk);
        if (single_count != 0 || double_count != 1)
            $fatal(2, "double click emitted a single or missed previous");
        repeat (10) @(negedge clk);
        if (single_count != 0)
            $fatal(3, "double click leaked a delayed single");

        click();
        repeat (10) @(negedge clk);
        if (single_count != 1 || double_count != 1)
            $fatal(4, "isolated click did not resolve once");

        click();
        context_id = 4'd4;
        repeat (10) @(negedge clk);
        if (single_count != 1 || double_count != 1)
            $fatal(5, "state change leaked a pending click into feedback");

        click();
        @(negedge clk);
        long_pulse = 1'b1;
        @(negedge clk);
        long_pulse = 1'b0;
        repeat (10) @(negedge clk);
        if (single_count != 1 || double_count != 1)
            $fatal(6, "long press failed to cancel a pending click");

        click();
        active = 1'b0;
        repeat (10) @(negedge clk);
        if (single_count != 1 || double_count != 1)
            $fatal(7, "leaving practice leaked a pending click");

        active = 1'b1;
        click();
        // A second release exactly on the expiry cycle wins over timeout.
        repeat (7) @(negedge clk);
        short_pulse = 1'b1;
        @(negedge clk); short_pulse = 1'b0;
        repeat (10) @(negedge clk);
        if (single_count != 1 || double_count != 2)
            $fatal(8, "expiry-cycle second release did not win over single");

        click();
        @(negedge clk); rst = 1'b1;
        @(negedge clk); rst = 1'b0;
        repeat (10) @(negedge clk);
        if (single_count != 1 || double_count != 2)
            $fatal(9, "reset leaked a pending click");

        $display("TEST_PASS tb_learning_key_double_click");
        $finish;
    end
endmodule
