`timescale 1ns/1ps
module tb_ambient_brightness;
reg clk=0, pixel_clk=0, rst=1;
always #10 clk=~clk;
always #20 pixel_clk=~pixel_clk;
reg [15:0] raw=0;
reg sample=0,sensor=0,settings=0,selector=0,dec=0,inc=0,uart_toggle=0;
reg signed [2:0] uart_bright=0;
wire signed [2:0] level,brightness;
wire valid,enabled,toggle;
wire [15:0] filtered;
wire [1:0] contrast;
wire osd,subtitle;
reg frame=0;
ambient_brightness #(.STALE_CYCLES(400),.CONFIRM_SAMPLES(3)) filter (
    .clk(clk),.rst(rst),.sample_raw(raw),.sample_valid(sample),.sensor_valid(sensor),
    .watchdog_tick(1'b1),
    .level(level),.valid(valid),.filtered_raw(filtered));
video_control_arbiter #(.ENABLE_AMBIENT(1)) arb (
    .clk(clk),.rst(rst),.uart_brightness(uart_bright),.uart_contrast(2'd1),
    .uart_osd_enable(1'b1),.uart_subtitle_enable(1'b1),.uart_control_toggle(uart_toggle),
    .settings_active(settings),.select_parameter_async(2'b00),
    .zoom_next_pulse(1'b0),.zoom_prev_pulse(1'b0),.decrement_pulse(dec),
    .increment_pulse(inc),.auto_selector_async(selector),.ambient_level(level),
    .ambient_valid(valid),.auto_brightness_enable(enabled),.brightness(brightness),
    .contrast(contrast),.osd_enable(osd),.subtitle_enable(subtitle),.control_toggle(toggle),
    .zoom_level(),.zoom_image_index(),.zoom_request_toggle(),.editing_parameter(),
    .zoom_lookup_index(2'd0),.zoom_lookup_level(),
    .eye_comfort_enable());
video_effects_osd #(.ENABLE_AMBIENT_OSD(1)) video (
    .pixel_clk(pixel_clk),.pixel_rst(rst),.frame_boundary(frame),
    .in_hs(1'b0),.in_vs(1'b0),.in_de(1'b0),.in_rgb(24'h808080),
    .source_brightness(brightness),.source_contrast(contrast),
    .source_osd_enable(osd),.source_subtitle_enable(subtitle),.source_control_toggle(toggle),
    .source_ambient_enable(enabled),.source_ambient_ready(valid),
    .source_zoom_preview_level(3'd2),.display_image_idx(4'd0),.display_zoom_level(3'd2),
    .display_valid(1'b0),.transition_active(1'b0),.source_target_image_idx(4'd0),
    .source_wrong_bitmap(3'd0),.source_state_code(4'd7),.source_state_toggle(1'b0),.source_auto_play(1'b0),
    .source_volume_level(3'd2),.source_volume_toggle(1'b0),.source_speed_level(2'd1),
    .source_speed_toggle(1'b0),.voice_progress(9'd0),.voice_clip(2'd0),.voice_valid(1'b0),
    .source_eye_comfort_enable(1'b0),.source_lesson_subtitle_active(1'b0),
    .source_lesson_subtitle_clip(2'd0),.source_lesson_subtitle_cue(5'd0),
    .source_lesson_subtitle_toggle(1'b0),.eye_filter_enable(),
    .out_hs(),.out_vs(),.out_de(),.out_rgb());
task check(input bit ok,input string message);
    if(!ok) begin $display("TEST_FAIL %s level=%d bright=%d",message,level,brightness); $fatal(1); end
endtask
task measure(input [15:0] value);
    begin
        @(negedge clk); raw=value; sample=1; sensor=1;
        @(negedge clk); sample=0; repeat(8) @(negedge clk);
    end
endtask
task key(input bit up);
    begin @(negedge clk); inc=up; dec=!up;
        @(negedge clk); inc=0; dec=0; repeat(8) @(negedge clk); end
endtask
task commit;
    begin repeat(10) @(negedge pixel_clk); frame=1;
        @(negedge pixel_clk); frame=0; end
endtask
task check_setting_auto(input bit expected_on);
    begin
        force video.state_active=4'd7;
        force video.pixel_y=10'd0;
        force video.pixel_x=10'd448;
        #1; check(video.status_region && video.status_code==8'h82,"auto label follows eye comfort");
        force video.pixel_x=10'd464;
        #1; check(video.status_code==8'h83,"auto label second glyph");
        force video.pixel_x=10'd480;
        #1; check(video.status_code==8'h86,"auto brightness label third glyph");
        force video.pixel_x=10'd496;
        #1; check(video.status_code==8'h87,"auto brightness label fourth glyph");
        force video.pixel_x=10'd512;
        #1; check(video.status_code==8'h3a,"auto brightness label colon");
        force video.pixel_x=10'd528;
        #1; check(video.status_code==(expected_on ? 8'h84 : 8'h85),"auto on/off setting");
        force video.pixel_x=10'd544;
        #1; check(!video.status_region,"settings label extends outside its band");
        force video.pixel_x=10'd80;
        #1; check(video.status_code==8'h86,"brightness did not move into removed auto slot");
        force video.pixel_x=10'd160;
        #1; check(video.status_code==8'h20,"brightness status suffix was not removed");
        force video.pixel_x=10'd176;
        #1; check(video.status_code==8'h88,"contrast did not follow brightness");
        force video.pixel_x=10'd256;
        #1; check(video.status_code==8'hC0,"zoom did not follow contrast");
        force video.pixel_x=10'd368;
        #1; check(video.status_code==8'hC2,"eye comfort did not follow zoom");
        release video.pixel_x;
        release video.pixel_y;
        release video.state_active;
    end
endtask
integer i;
initial begin
    repeat(8) @(negedge clk); rst=0; repeat(8) @(negedge clk);
    check(!enabled && brightness==0 && !valid,"manual startup default");
    measure(0); measure(0); check(level==0,"three-sample debounce");
    measure(0); check(level==-1,"first dark step");
    repeat(3) measure(0); check(level==-2 && brightness==0,"manual default ignores sensor");
    settings=1; selector=1; repeat(8) @(negedge clk); key(1);
    check(enabled && brightness==-2,"explicit automatic startup selection");
    settings=0; selector=0;
    check(video.brightness_active==0,"no midframe brightness update");
    commit(); check(video.brightness_active==-2 && video.ambient_ready_active,"frame commit");
    for(i=0;i<40;i=i+1) measure(65535);
    check(level==2 && brightness==2 && filtered>65000,"full-scale filter cannot overflow");
    commit(); check(video.brightness_active==2,"positive frame commit");
    // Manual saturation still disables auto; resume explicitly via SW3.
    settings=1; repeat(8) @(negedge clk); key(1);
    check(!enabled && brightness==2,"manual override at end stop");
    check(video.ambient_enable_active,"setting changed before frame boundary");
    commit(); check(!video.ambient_enable_active,"manual off did not commit");
    check_setting_auto(0);
    key(0); check(brightness==1,"manual decrement");
    selector=1; repeat(8) @(negedge clk); key(1);
    check(enabled && brightness==2,"explicit automatic resume");
    check(!video.ambient_enable_active,"automatic on changed before frame boundary");
    commit(); check(video.ambient_enable_active,"automatic on did not commit");
    check_setting_auto(1);
    sensor=0; repeat(8) @(negedge clk);
    check(!valid && brightness==1,"disconnect restores retained manual value");
    commit(); check(video.ambient_enable_active && !video.ambient_ready_active,"error OSD state");
    repeat(7) measure(0); check(brightness==-2,"recovery after reconnect");
    // A silent producer cannot retain an apparently healthy automatic value.
    repeat(410) @(negedge clk); check(!valid && brightness==1,"stale data fallback");
    selector=0; settings=0; uart_bright=-1;
    @(negedge clk); uart_toggle=~uart_toggle; repeat(8) @(negedge clk);
    check(!enabled && brightness==-1,"UART override");
    repeat(9) measure(65535); check(brightness==-1,"manual value immune to sensor");
    // Fresh 100-lux region, jitter remains inside low/normal hysteresis.
    sensor=0; repeat(4) @(negedge clk); measure(180);
    repeat(15) measure(180); check(level==0,"nominal 150 lux remains neutral");
    repeat(10) begin measure(150); measure(210); end
    check(level==0,"boundary noise no hunting");
    rst=1; uart_toggle=0; sensor=0;
    repeat(8) @(negedge clk); rst=0; repeat(8) @(negedge clk);
    check(brightness==0 && !enabled,"reset returns to manual preference");
    $display("TEST_PASS ambient extremes, hysteresis, debounce, stale, reconnect, manual/UART, frame commit");
    $finish;
end
initial begin #2000000; $fatal(1,"TEST_FAIL timeout"); end
endmodule
