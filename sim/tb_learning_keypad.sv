`timescale 1ns/1ps

module tb_learning_keypad;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [1:0] key_n_async = 2'b11;
    reg [1:0] nav_long_mode = 2'b00;
    wire [1:0] pressed;
    wire [1:0] short_press_pulse;
    wire [1:0] long_press_pulse;
    integer short_count = 0;
    integer long_count = 0;

    always #5 clk = ~clk;

    learning_keypad #(
        .KEY_COUNT(2),
        .COUNTER_WIDTH(4),
        .DEBOUNCE_CYCLES(3),
        .LONG_PRESS_CYCLES(8),
        .NAV_LONG_PRESS_CYCLES(4)
    ) dut (
        .clk(clk),
        .rst(rst),
        .key_n_async(key_n_async),
        .nav_long_mode(nav_long_mode),
        .pressed(pressed),
        .short_press_pulse(short_press_pulse),
        .long_press_pulse(long_press_pulse)
    );

    always @(posedge clk) begin
        if (short_press_pulse[0] || short_press_pulse[1])
            short_count <= short_count + 1;
        if (long_press_pulse[0] || long_press_pulse[1])
            long_count <= long_count + 1;
    end

    task automatic drive_key(input integer index, input bit level_n);
        begin
            @(negedge clk);
            key_n_async[index] = level_n;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Contact chatter shorter than the debounce interval must be ignored.
        drive_key(0, 1'b0);
        drive_key(0, 1'b1);
        drive_key(0, 1'b0);
        drive_key(0, 1'b1);
        repeat (4) @(posedge clk);
        #1;
        if (pressed != 2'b00 || short_count != 0 || long_count != 0)
            $fatal(1, "bounce generated a key event");

        // A stable press followed by release generates one short event.
        drive_key(0, 1'b0);
        wait (pressed[0]);
        repeat (2) @(posedge clk);
        drive_key(0, 1'b1);
        wait (short_press_pulse[0]);
        @(posedge clk);
        #1;
        if (pressed[0] || short_count != 1 || long_count != 0)
            $fatal(2, "short press classification failed");

        // KEY4 path: a held key generates exactly one long event and no short
        // event on release, even when it remains held beyond the threshold.
        drive_key(1, 1'b0);
        wait (pressed[1]);
        wait (long_press_pulse[1]);
        repeat (8) @(posedge clk);
        drive_key(1, 1'b1);
        wait (!pressed[1]);
        repeat (2) @(posedge clk);
        #1;
        if (short_count != 1 || long_count != 1)
            $fatal(3, "long press was duplicated or leaked a short event");

        // Navigation mode is captured when the debounced press begins. It
        // classifies a page-switch hold early, without a short on release.
        nav_long_mode[0] = 1'b1;
        drive_key(0, 1'b0);
        wait (pressed[0]);
        nav_long_mode[0] = 1'b0;
        wait (long_press_pulse[0]);
        repeat (8) @(posedge clk);
        drive_key(0, 1'b1);
        wait (!pressed[0]);
        repeat (2) @(posedge clk);
        #1;
        if (short_count != 1 || long_count != 2)
            $fatal(4, "navigation hold leaked a short event");

        // Outside navigation mode a medium hold is still a short release.
        drive_key(0, 1'b0);
        wait (pressed[0]);
        repeat (5) @(posedge clk);
        drive_key(0, 1'b1);
        wait (short_press_pulse[0]);
        repeat (2) @(posedge clk);
        if (short_count != 2 || long_count != 2)
            $fatal(5, "normal hold used navigation threshold");

        $display("TEST_PASS tb_learning_keypad");
        $finish;
    end
endmodule
