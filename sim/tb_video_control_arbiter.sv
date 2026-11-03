`timescale 1ns/1ps

module tb_video_control_arbiter;

reg clk;
reg rst;
reg signed [2:0] uart_brightness;
reg [1:0] uart_contrast;
reg uart_osd_enable;
reg uart_subtitle_enable;
reg uart_control_toggle;
reg settings_active;
reg [1:0] select_parameter_async;
reg zoom_next_pulse;
reg zoom_prev_pulse;
reg decrement_pulse;
reg increment_pulse;
wire signed [2:0] brightness;
wire [1:0] contrast;
wire osd_enable;
wire subtitle_enable;
wire control_toggle;
wire [2:0] zoom_level;
wire [1:0] zoom_image_index;
reg [1:0] zoom_lookup_index;
wire [2:0] zoom_lookup_level;
wire zoom_request_toggle;
wire [1:0] editing_parameter;
wire eye_comfort_enable;
wire auto_brightness_enable;

integer update_count;
reg previous_toggle;
integer zoom_update_count;
reg previous_zoom_toggle;

video_control_arbiter #(
    .ZOOM_APPLY_DELAY_CYCLES(6),
    .ZOOM_APPLY_COUNTER_WIDTH(4)
) dut (
    .clk(clk),
    .rst(rst),
    .uart_brightness(uart_brightness),
    .uart_contrast(uart_contrast),
    .uart_osd_enable(uart_osd_enable),
    .uart_subtitle_enable(uart_subtitle_enable),
    .uart_control_toggle(uart_control_toggle),
    .settings_active(settings_active),
    .select_parameter_async(select_parameter_async),
    .zoom_next_pulse(zoom_next_pulse),
    .zoom_prev_pulse(zoom_prev_pulse),
    .decrement_pulse(decrement_pulse),
    .increment_pulse(increment_pulse),
    .auto_brightness_enable(auto_brightness_enable),
    .brightness(brightness),
    .contrast(contrast),
    .osd_enable(osd_enable),
    .subtitle_enable(subtitle_enable),
    .control_toggle(control_toggle),
    .zoom_level(zoom_level),
    .zoom_image_index(zoom_image_index),
    .zoom_lookup_index(zoom_lookup_index),
    .zoom_lookup_level(zoom_lookup_level),
    .zoom_request_toggle(zoom_request_toggle),
    .editing_parameter(editing_parameter),
    .eye_comfort_enable(eye_comfort_enable)
);

always #5 clk = ~clk;

always @(posedge clk) begin
    if (rst) begin
        update_count <= 0;
        previous_toggle <= 1'b0;
        zoom_update_count <= 0;
        previous_zoom_toggle <= 1'b0;
    end else begin
        if (control_toggle != previous_toggle)
            update_count <= update_count + 1;
        previous_toggle <= control_toggle;
        if (zoom_request_toggle != previous_zoom_toggle)
            zoom_update_count <= zoom_update_count + 1;
        previous_zoom_toggle <= zoom_request_toggle;
    end
end

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

task pulse_zoom_next;
begin
    @(negedge clk);
    zoom_next_pulse = 1'b1;
    @(negedge clk);
    zoom_next_pulse = 1'b0;
end
endtask

task pulse_zoom_prev;
begin
    @(negedge clk);
    zoom_prev_pulse = 1'b1;
    @(negedge clk);
    zoom_prev_pulse = 1'b0;
end
endtask

task check_equal;
    input condition;
    input [8*80-1:0] message;
begin
    if (!condition) begin
        $display("TEST_FAIL: %0s", message);
        $fatal(1);
    end
end
endtask

initial begin
    clk = 1'b0;
    rst = 1'b1;
    uart_brightness = 3'sd0;
    uart_contrast = 2'd1;
    uart_osd_enable = 1'b1;
    uart_subtitle_enable = 1'b1;
    uart_control_toggle = 1'b0;
    settings_active = 1'b0;
    select_parameter_async = 2'b00;
    zoom_next_pulse = 1'b0;
    zoom_prev_pulse = 1'b0;
    zoom_lookup_index = 2'd0;
    decrement_pulse = 1'b0;
    increment_pulse = 1'b0;

    repeat (3) @(negedge clk);
    rst = 1'b0;
    settings_active = 1'b1;
    check_equal(eye_comfort_enable && !auto_brightness_enable,
                "reset defaults for eye comfort and auto brightness are wrong");

    // Brightness saturates at -2; the third decrement must not publish.
    pulse_decrement();
    pulse_decrement();
    pulse_decrement();
    @(negedge clk);
    check_equal(brightness == -3'sd2, "brightness did not saturate at -2");
    check_equal(update_count == 2, "brightness saturation published an extra update");

    // SW1 selects contrast; allow the asynchronous level through two flops.
    select_parameter_async = 2'b01;
    repeat (3) @(negedge clk);
    check_equal(editing_parameter == 2'b01, "selection did not switch to contrast");
    pulse_decrement();
    pulse_decrement();
    pulse_increment();
    pulse_increment();
    pulse_increment();
    pulse_increment();
    @(negedge clk);
    check_equal(contrast == 2'd3, "contrast did not saturate at 3");
    check_equal(update_count == 6, "contrast saturation update count is wrong");

    // A UART mailbox update wins atomically and becomes the new key baseline.
    @(negedge clk);
    uart_brightness = 3'sd2;
    uart_contrast = 2'd1;
    uart_osd_enable = 1'b0;
    uart_subtitle_enable = 1'b0;
    uart_control_toggle = ~uart_control_toggle;
    repeat (2) @(negedge clk);
    check_equal((brightness == 3'sd2) && (contrast == 2'd1),
                "UART values were not copied atomically");
    check_equal(!osd_enable && !subtitle_enable,
                "UART enable bits were not retained");
    check_equal(update_count == 7, "UART update was not published once");

    pulse_decrement();
    @(negedge clk);
    check_equal(contrast == 2'd0, "key edit did not start from UART value");
    check_equal(update_count == 8, "key edit after UART did not publish once");

    // SW2/SW1=10 selects real-time zoom.  It has five saturated levels:
    // 50, 75, 100, 125 and 150 percent (reset level is 100 percent).
    select_parameter_async = 2'b10;
    repeat (4) @(negedge clk);
    check_equal(editing_parameter == 2'b10, "selection did not switch to zoom");
    check_equal((zoom_image_index == 2'd0) && (zoom_level == 3'd2),
                "image zero did not open at its default zoom");
    check_equal((update_count == 9) && (zoom_update_count == 0),
                "zoom OSD feedback was not immediate or reread started too early");
    repeat (8) @(negedge clk);
    check_equal(zoom_update_count == 1,
                "settled image selection was not published once");
    pulse_decrement();
    pulse_decrement();
    pulse_decrement();
    @(negedge clk);
    check_equal(zoom_level == 3'd0, "zoom did not saturate at 50 percent");
    check_equal(zoom_update_count == 1,
                "rapid zoom decrements were not coalesced before apply");
    repeat (8) @(negedge clk);
    check_equal(zoom_update_count == 2,
                "settled lower zoom was not published once");
    pulse_increment();
    pulse_increment();
    pulse_increment();
    pulse_increment();
    pulse_increment();
    @(negedge clk);
    check_equal(zoom_level == 3'd4, "zoom did not saturate at 150 percent");
    check_equal(zoom_update_count == 2,
                "rapid zoom increments were not coalesced before apply");
    repeat (8) @(negedge clk);
    check_equal(zoom_update_count == 3,
                "settled upper zoom was not published once");

    // Long KEY2 selects another image. It starts at 100 percent and changing it
    // must not overwrite image zero's stored 150-percent value.
    pulse_zoom_next();
    repeat (2) @(negedge clk);
    check_equal((zoom_image_index == 2'd1) && (zoom_level == 3'd2),
                "image one did not restore its independent default zoom");
    pulse_decrement();
    @(negedge clk);
    check_equal(zoom_level == 3'd1, "image one zoom edit failed");
    pulse_zoom_prev();
    repeat (2) @(negedge clk);
    check_equal((zoom_image_index == 2'd0) && (zoom_level == 3'd4),
                "image zero zoom was overwritten by image one");
    pulse_zoom_next();
    repeat (2) @(negedge clk);
    check_equal((zoom_image_index == 2'd1) && (zoom_level == 3'd1),
                "image one zoom was not restored");
    repeat (8) @(negedge clk);
    check_equal(zoom_update_count == 4,
                "rapid image/zoom selections were not coalesced to the final request");

    // Long navigation stops at the first and third learning images.
    pulse_zoom_next();
    pulse_zoom_next();
    pulse_zoom_next();
    pulse_zoom_next();
    @(negedge clk);
    check_equal(zoom_image_index == 2'd2, "zoom next reached a practice image");
    check_equal(update_count == 20, "zoom boundary keys published a page change");
    pulse_zoom_prev();
    pulse_zoom_prev();
    pulse_zoom_prev();
    pulse_zoom_prev();
    @(negedge clk);
    check_equal(zoom_image_index == 2'd0, "zoom previous wrapped before image one");
    repeat (8) @(negedge clk);
    check_equal(zoom_lookup_level == 3'd4, "page zero lookup lost its zoom");
    zoom_lookup_index = 2'd1;
    #1;
    check_equal(zoom_lookup_level == 3'd1, "page one lookup lost its zoom");
    zoom_lookup_index = 2'd2;
    #1;
    check_equal(zoom_lookup_level == 3'd2, "page two lookup changed its default");

    // Leaving SETTINGS ignores edit pulses; SW1 remains the visible selector.
    settings_active = 1'b0;
    select_parameter_async = 2'b00;
    repeat (3) @(negedge clk);
    pulse_increment();
    @(negedge clk);
    check_equal(editing_parameter == 2'b00, "parameter selection did not synchronize low");
    check_equal((brightness == 3'sd2) && (contrast == 2'd0),
                "inactive SETTINGS key changed a value");
    check_equal(update_count == 22, "inactive SETTINGS key published an update");

    // UART wins a same-cycle collision with a physical increment.
    settings_active = 1'b1;
    select_parameter_async = 2'b01;
    repeat (3) @(negedge clk);
    @(negedge clk);
    uart_brightness = -3'sd1;
    uart_contrast = 2'd2;
    uart_control_toggle = ~uart_control_toggle;
    increment_pulse = 1'b1;
    @(negedge clk);
    increment_pulse = 1'b0;
    repeat (2) @(negedge clk);
    check_equal((brightness == -3'sd1) && (contrast == 2'd2),
                "UART did not win a same-cycle key collision");
    check_equal(update_count == 23, "collision published more than one update");

    // Contradictory key pulses are defensive no-ops.
    decrement_pulse = 1'b1;
    increment_pulse = 1'b1;
    @(negedge clk);
    decrement_pulse = 1'b0;
    increment_pulse = 1'b0;
    repeat (2) @(negedge clk);
    check_equal((brightness == -3'sd1) && (contrast == 2'd2),
                "simultaneous decrement/increment changed a value");
    check_equal(update_count == 23, "contradictory keys published an update");

    // Eye-comfort selector 11 must not edit the legacy image parameters.
    select_parameter_async = 2'b11;
    repeat (3) @(negedge clk);
    pulse_decrement();
    @(negedge clk);
    check_equal((brightness == -3'sd1) && (contrast == 2'd2) &&
                (zoom_level == 3'd4),
                "eye comfort changed an image parameter");
    check_equal(zoom_update_count == 6,
                "eye comfort requested a BMP reread");
    check_equal(!eye_comfort_enable, "explicit off failed");
    pulse_increment();
    @(negedge clk);
    check_equal(eye_comfort_enable, "explicit on failed");
    pulse_increment();
    @(negedge clk);
    check_equal(eye_comfort_enable, "repeated on toggled preference");
    decrement_pulse = 1'b1;
    increment_pulse = 1'b1;
    @(negedge clk);
    decrement_pulse = 1'b0;
    increment_pulse = 1'b0;
    check_equal(eye_comfort_enable, "contradictory keys changed preference");
    settings_active = 1'b0;
    pulse_decrement();
    @(negedge clk);
    check_equal(eye_comfort_enable, "preference changed outside SETTINGS");
    settings_active = 1'b1;
    pulse_decrement();
    @(negedge clk);
    check_equal(!eye_comfort_enable, "explicit off did not clear preference");
    check_equal(update_count == 23 && zoom_update_count == 6,
                "eye comfort altered legacy control or zoom toggles");

    $display("TEST_PASS: video_control_arbiter");
    $finish;
end

endmodule
