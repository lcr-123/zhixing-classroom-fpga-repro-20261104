`timescale 1ns/1ps

module tb_key_navigation_integration;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg [1:0] key_n = 2'b11;
    reg [3:0] app_state = 4'd7;
    wire [1:0] pressed, short_pulse, long_pulse;
    wire single_pulse, double_pulse;
    wire [1:0] editing_parameter;
    wire [2:0] zoom_level;
    wire [1:0] zoom_image_index;
    wire zoom_request_toggle;
    integer previous_count = 0;
    integer edit_count = 0;
    integer home_count = 0;

    wire settings_zoom = app_state == 4'd7 && editing_parameter == 2'b10;
    wire practice = app_state == 4'd3;
    wire previous_event = practice && (long_pulse[0] || double_pulse);
    wire edit_event = settings_zoom && (single_pulse || short_pulse[1]);

    learning_keypad #(
        .KEY_COUNT(2), .COUNTER_WIDTH(5), .DEBOUNCE_CYCLES(2),
        .LONG_PRESS_CYCLES(12), .NAV_LONG_PRESS_CYCLES(7)
    ) keys (
        .clk(clk), .rst(rst), .key_n_async(key_n),
        .nav_long_mode({1'b0, settings_zoom || practice}),
        .pressed(pressed), .short_press_pulse(short_pulse),
        .long_press_pulse(long_pulse)
    );
    learning_key_double_click #(
        .WINDOW_CYCLES(30), .COUNTER_WIDTH(5)
    ) clicks (
        .clk(clk), .rst(rst), .active(practice || settings_zoom),
        .context_id(app_state),
        .short_pulse(short_pulse[0]), .long_pulse(long_pulse[0]),
        .single_pulse(single_pulse), .double_pulse(double_pulse)
    );
    video_control_arbiter #(
        .ZOOM_APPLY_DELAY_CYCLES(80), .ZOOM_APPLY_COUNTER_WIDTH(7)
    ) settings (
        .clk(clk), .rst(rst), .uart_brightness(3'sd0),
        .uart_contrast(2'd1), .uart_osd_enable(1'b1),
        .uart_subtitle_enable(1'b1), .uart_control_toggle(1'b0),
        .settings_active(app_state == 4'd7),
        .select_parameter_async(2'b10),
        .zoom_next_pulse(long_pulse[0]),
        .zoom_prev_pulse(settings_zoom && double_pulse),
        .decrement_pulse(app_state == 4'd7 && single_pulse),
        .increment_pulse(app_state == 4'd7 && short_pulse[1]),
        .brightness(), .contrast(), .osd_enable(),
        .subtitle_enable(), .control_toggle(),
        .zoom_level(zoom_level), .zoom_image_index(zoom_image_index),
        .zoom_lookup_index(2'd0), .zoom_lookup_level(),
        .zoom_request_toggle(zoom_request_toggle),
        .editing_parameter(editing_parameter)
    );
    always @(posedge clk) begin
        if (previous_event) previous_count <= previous_count + 1;
        if (edit_event) edit_count <= edit_count + 1;
        if (long_pulse[1]) home_count <= home_count + 1;
    end

    task automatic press(input integer key_index, input integer held_cycles);
        begin
            @(negedge clk); key_n[key_index] = 0;
            wait (pressed[key_index]);
            repeat (held_cycles) @(negedge clk);
            key_n[key_index] = 1;
            wait (!pressed[key_index]);
            repeat (3) @(negedge clk);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (8) @(negedge clk);
        if (editing_parameter != 2'b10) $fatal(1, "zoom selector not ready");

        press(0, 1);
        repeat (35) @(negedge clk);
        if (zoom_level != 1 || zoom_image_index != 0 || edit_count != 1)
            $fatal(1, "short KEY2 did not edit only the current image");
        press(0, 8);
        if (zoom_image_index != 1 || zoom_level != 2 || edit_count != 1)
            $fatal(1, "long KEY2 page switch also changed zoom");
        press(0, 1);
        press(0, 1);
        if (zoom_image_index != 0 || zoom_level != 1 || edit_count != 1)
            $fatal(1, "double KEY2 did not restore previous image zoom");
        repeat (35) @(negedge clk);
        if (edit_count != 1)
            $fatal(1, "double KEY2 leaked a delayed zoom edit");
        press(0, 1);
        press(0, 8);
        if (zoom_image_index != 1 || zoom_level != 2 || edit_count != 1)
            $fatal(1, "long navigation did not cancel a pending zoom click");
        press(0, 1);
        press(0, 1);
        if (zoom_image_index != 0 || zoom_level != 1 || edit_count != 1)
            $fatal(1, "previous image did not retain its zoom after navigation");
        press(1, 13);
        if (home_count != 1 || zoom_image_index != 0 || zoom_level != 1)
            $fatal(1, "long KEY4 did not request HOME or changed zoom");

        app_state = 4'd3;
        repeat (3) @(negedge clk);
        press(0, 8);
        if (previous_count != 1 || edit_count != 1)
            $fatal(1, "practice long KEY2 did not request previous");
        press(0, 1);
        press(0, 1);
        repeat (3) @(negedge clk);
        if (previous_count != 2)
            $fatal(1, "practice double KEY2 did not request previous");
        repeat (35) @(negedge clk);
        if (previous_count != 2)
            $fatal(1, "previous event repeated after click window");

        $display("TEST_PASS tb_key_navigation_integration");
        $finish;
    end
endmodule
