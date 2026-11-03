`timescale 1ns/1ps

module tb_lesson_volume_control;

reg clk = 1'b0;
reg rst = 1'b1;
reg learning_active = 1'b0;
reg adjust_switch_async = 1'b0;
reg speed_switch_async = 1'b0;
reg decrement_pulse = 1'b0;
reg increment_pulse = 1'b0;
wire adjust_mode_active;
wire speed_adjust_active;
wire [2:0] volume_level;
wire control_toggle;
wire [1:0] speed_level;
wire speed_toggle;
reg previous_toggle;

lesson_volume_control dut (
    .clk                (clk),
    .rst                (rst),
    .learning_active    (learning_active),
    .adjust_switch_async(adjust_switch_async),
    .speed_switch_async (speed_switch_async),
    .decrement_pulse    (decrement_pulse),
    .increment_pulse    (increment_pulse),
    .adjust_mode_active (adjust_mode_active),
    .speed_adjust_active(speed_adjust_active),
    .volume_level       (volume_level),
    .control_toggle     (control_toggle),
    .speed_level        (speed_level),
    .speed_toggle       (speed_toggle)
);

always #5 clk = ~clk;

task check;
    input condition;
    input [8*96-1:0] message;
begin
    if (!condition) begin
        $display("TEST_FAIL: %0s", message);
        $fatal(1);
    end
end
endtask

task pulse_decrement;
begin
    @(negedge clk);
    decrement_pulse = 1'b1;
    @(negedge clk);
    decrement_pulse = 1'b0;
end
endtask

task pulse_increment;
begin
    @(negedge clk);
    increment_pulse = 1'b1;
    @(negedge clk);
    increment_pulse = 1'b0;
end
endtask

initial begin
    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);
    check((volume_level == 3'd4) && !adjust_mode_active &&
          (speed_level == 2'd2) && !speed_adjust_active,
          "reset did not select full volume and 1.25x speed");

    adjust_switch_async = 1'b1;
    repeat (3) @(negedge clk);
    pulse_decrement();
    check((volume_level == 3'd4) && !adjust_mode_active,
          "volume changed outside the learning state");

    learning_active = 1'b1;
    @(negedge clk);
    check(adjust_mode_active, "SW4 did not enable learning volume mode");

    previous_toggle = control_toggle;
    pulse_decrement();
    check((volume_level == 3'd3) &&
          (control_toggle != previous_toggle),
          "KEY2 did not lower narration volume");
    pulse_decrement();
    pulse_decrement();
    pulse_decrement();
    check(volume_level == 3'd0, "volume did not reach its lower limit");
    previous_toggle = control_toggle;
    pulse_decrement();
    check((volume_level == 3'd0) &&
          (control_toggle == previous_toggle),
          "lower-limit press emitted a false control update");

    pulse_increment();
    pulse_increment();
    pulse_increment();
    pulse_increment();
    check(volume_level == 3'd4, "KEY4 did not restore full volume");
    previous_toggle = control_toggle;
    pulse_increment();
    check((volume_level == 3'd4) &&
          (control_toggle == previous_toggle),
          "upper-limit press emitted a false control update");

    @(negedge clk);
    decrement_pulse = 1'b1;
    increment_pulse = 1'b1;
    @(negedge clk);
    decrement_pulse = 1'b0;
    increment_pulse = 1'b0;
    check(volume_level == 3'd4,
          "simultaneous volume keys did not fail safely");

    adjust_switch_async = 1'b0;
    repeat (3) @(negedge clk);
    pulse_decrement();
    check((volume_level == 3'd4) && !adjust_mode_active,
          "normal learning navigation altered narration volume");

    speed_switch_async = 1'b1;
    repeat (3) @(negedge clk);
    check(speed_adjust_active, "SW3 did not enter speed mode");
    previous_toggle = speed_toggle;
    pulse_decrement();
    check(speed_level == 2'd1 && speed_toggle != previous_toggle,
          "KEY2 did not select 1.00x");
    previous_toggle = speed_toggle;
    pulse_decrement();
    check(speed_level == 2'd0 && speed_toggle != previous_toggle,
          "KEY2 did not select 0.75x");
    previous_toggle = speed_toggle;
    pulse_decrement();
    check(speed_level == 2'd0 && speed_toggle == previous_toggle,
          "speed lower limit emitted a false update");
    pulse_increment();
    pulse_increment();
    check(speed_level == 2'd2, "KEY4 did not select 1.25x");
    previous_toggle = speed_toggle;
    pulse_increment();
    check(speed_level == 2'd2 && speed_toggle == previous_toggle,
          "speed upper limit emitted a false update");
    @(negedge clk);
    decrement_pulse = 1'b1;
    increment_pulse = 1'b1;
    @(negedge clk);
    decrement_pulse = 1'b0;
    increment_pulse = 1'b0;
    check(speed_level == 2'd2, "simultaneous speed keys changed the level");
    adjust_switch_async = 1'b1;
    repeat (3) @(negedge clk);
    check(adjust_mode_active && !speed_adjust_active,
          "SW4 did not take priority over SW3");
    pulse_decrement();
    check(volume_level == 3'd3 && speed_level == 2'd2,
          "SW4 priority changed both volume and speed");
    adjust_switch_async = 1'b0;
    speed_switch_async = 1'b0;
    repeat (3) @(negedge clk);
    pulse_decrement();
    check(speed_level == 2'd2 && !speed_adjust_active,
          "normal navigation changed retained speed");

    learning_active = 1'b0;
    adjust_switch_async = 1'b1;
    repeat (3) @(negedge clk);
    check(!adjust_mode_active,
          "volume mode remained active after leaving learning");

    $display("TEST_PASS: lesson_volume_control");
    $finish;
end

endmodule
