`timescale 1ns/1ps
module tb_eye_comfort;
reg clk=0, pixel_clk=0, rst=1, pixel_rst=1;
always #10 clk=~clk;
always #19 pixel_clk=~pixel_clk;
reg [1:0] key_n=3, selector=3;
reg [3:0] app_state=7;
wire [1:0] pressed, short_event, long_event;
wire preference, filter_enable;
integer home_events=0;
learning_keypad #(.KEY_COUNT(2), .COUNTER_WIDTH(6),
    .DEBOUNCE_CYCLES(2), .LONG_PRESS_CYCLES(16)) keys (
    .clk(clk), .rst(rst), .key_n_async(key_n), .nav_long_mode(2'b00),
    .pressed(pressed), .short_press_pulse(short_event),
    .long_press_pulse(long_event));
always @(posedge clk) if (!rst && long_event[1]) home_events=home_events+1;
video_control_arbiter controls (
    .clk(clk), .rst(rst), .uart_brightness(3'sd0), .uart_contrast(2'd1),
    .uart_osd_enable(1'b1), .uart_subtitle_enable(1'b1),
    .uart_control_toggle(1'b0), .settings_active(app_state==7),
    .select_parameter_async(selector), .zoom_next_pulse(1'b0),
    .zoom_prev_pulse(1'b0),
    .decrement_pulse(app_state==7 && short_event[0]),
    .increment_pulse(app_state==7 && short_event[1]),
    .brightness(), .contrast(), .osd_enable(), .subtitle_enable(),
    .control_toggle(), .zoom_level(), .zoom_image_index(),
    .zoom_lookup_index(2'd0), .zoom_lookup_level(),
    .zoom_request_toggle(), .editing_parameter(),
    .eye_comfort_enable(preference));
reg boundary=0, ih=0, iv=0, ide=0;
reg [23:0] rgb=0;
reg state_toggle=0;
wire oh, ov, ode;
wire [23:0] orgb;
video_effects_osd osd (
    .pixel_clk(pixel_clk), .pixel_rst(pixel_rst), .frame_boundary(boundary),
    .in_hs(ih), .in_vs(iv), .in_de(ide), .in_rgb(rgb),
    .source_brightness(3'sd0), .source_contrast(2'd1),
    .source_osd_enable(1'b1), .source_subtitle_enable(1'b0),
    .source_control_toggle(1'b0), .source_zoom_preview_level(3'd2),
    .display_image_idx(4'd0), .display_zoom_level(3'd2),
    .display_valid(1'b0), .transition_active(1'b0), .source_target_image_idx(4'd0),
    .source_wrong_bitmap(3'd0),.source_state_code(app_state), .source_state_toggle(state_toggle),
    .source_auto_play(1'b0), .source_eye_comfort_enable(preference),
    .source_volume_level(3'd4), .source_volume_toggle(1'b0),
    .source_speed_level(2'd1), .source_speed_toggle(1'b0),
    .voice_progress(9'd0), .voice_clip(2'd0), .voice_valid(1'b0),
    .source_lesson_subtitle_active(1'b0), .source_lesson_subtitle_clip(2'd0),
    .source_lesson_subtitle_cue(5'd0), .source_lesson_subtitle_toggle(1'b0),
    .eye_filter_enable(filter_enable), .out_hs(oh), .out_vs(ov),
    .out_de(ode), .out_rgb(orgb));
wire fh, fv, fde;
wire [23:0] frgb;
video_eye_comfort filter (
    .pixel_clk(pixel_clk), .pixel_rst(pixel_rst), .enable(filter_enable),
    .in_hs(oh), .in_vs(ov), .in_de(ode), .in_rgb(orgb),
    .out_hs(fh), .out_vs(fv), .out_de(fde), .out_rgb(frgb));
// A second instance validates all channel values, including the blanking
// contract, independently of OSD coordinates and its 2-cycle latency.
reg unit_enable=0;
wire uh, uv, ude;
wire [23:0] urgb;
video_eye_comfort unit_filter (
    .pixel_clk(pixel_clk), .pixel_rst(pixel_rst), .enable(unit_enable),
    .in_hs(ih), .in_vs(iv), .in_de(ide), .in_rgb(rgb),
    .out_hs(uh), .out_vs(uv), .out_de(ude), .out_rgb(urgb));
function [23:0] golden(input [23:0] value, input enabled);
    integer g,b;
    begin
        g=value[15:8]; b=value[7:0];
        golden=enabled ? {value[23:16],8'(g-g/16),8'(b-b/4)} : value;
    end
endfunction
integer checked=0, white_checked=0;
reg [23:0] want, unit_want;
reg wh,wv,wd,uih,uiv,uid;
always @(posedge pixel_clk) begin
    if (!pixel_rst) begin
        want=ode ? golden(orgb,filter_enable) : 24'd0;
        wh=oh; wv=ov; wd=ode;
        unit_want=ide ? golden(rgb,unit_enable) : 24'd0;
        uih=ih; uiv=iv; uid=ide;
        if (ode && orgb==24'hffffff && filter_enable) white_checked=white_checked+1;
        #1;
        if ({fh,fv,fde,frgb} !== {wh,wv,wd,want})
            $fatal(1,"OSD/filter pixel or timing mismatch");
        if ({uh,uv,ude,urgb} !== {uih,uiv,uid,unit_want})
            $fatal(1,"channel reference or timing mismatch rgb=%h",rgb);
        checked=checked+1;
    end
end
task press(input integer index, input integer duration);
    begin
        @(negedge clk); key_n[index]=0;
        wait(pressed[index]);
        repeat(duration) @(negedge clk);
        key_n[index]=1;
        wait(!pressed[index]);
        repeat(4) @(negedge clk);
    end
endtask
task frame;
    begin
        @(negedge pixel_clk); ide=0; boundary=1;
        @(negedge pixel_clk); boundary=0;
    end
endtask
task state_to(input [3:0] state_value, input expected);
    reg old_enable;
    begin
        old_enable=filter_enable;
        @(negedge clk); app_state=state_value; state_toggle=~state_toggle;
        repeat(9) @(negedge pixel_clk);
        if (filter_enable!==old_enable) $fatal(1,"state changed filter mid frame");
        frame();
        if (filter_enable!==expected) $fatal(1,"state %0d eligibility mismatch",state_value);
    end
endtask
integer i,j;
initial begin
    repeat(4) @(negedge clk); rst=0;
    @(negedge pixel_clk); pixel_rst=0;
    repeat(8) @(negedge clk);
    if(preference!==1) $fatal(1,"reset default not on");
    state_to(7,1);
    press(0,2);
    frame();
    if(preference!==0 || osd.eye_active!==0) $fatal(1,"explicit off before preview failed");
    press(1,2);
    if(preference!==1) $fatal(1,"short KEY4 did not enable");
    repeat(6) @(negedge pixel_clk);
    if(osd.eye_active!==0) $fatal(1,"preference committed mid frame");
    frame();
    if(osd.eye_active!==1 || filter_enable!==1) $fatal(1,"settings preview not enabled");
    // Check rendered SETTINGS status character cells and both Chinese glyphs.
    @(negedge pixel_clk); ide=1; rgb=24'hffffff;
    for(i=0;i<32;i=i+1) begin
        repeat(16) @(negedge pixel_clk);
        if(i==22 && osd.status_code!==8'hc2) $fatal(1,"missing eye label");
        if(i==25 && osd.status_code!==8'h84) $fatal(1,"missing ON status");
    end
    @(negedge pixel_clk); ide=0;
    if(osd.font_row(8'hc2,4'd5)==0 || osd.font_row(8'hc3,4'd5)==0)
        $fatal(1,"missing Chinese glyph");
    // Compare an actual white pixel at the output while remaining in SETTINGS.
    // Key changes must wait for the safe frame boundary in both directions.
    repeat(4) @(negedge pixel_clk);
    @(negedge pixel_clk); ide=1; rgb=24'hffffff;
    // x >= 432 avoids the status bar's intentional dark background.
    repeat(524) @(negedge pixel_clk);
    if(!fde || frgb!==24'hfff0c0) $fatal(1,"settings warm preview pixel missing");
    press(0,2);
    repeat(6) @(negedge pixel_clk);
    if(filter_enable!==1 || frgb!==24'hfff0c0)
        $fatal(1,"settings preview disabled before frame boundary");
    frame();
    if(filter_enable!==0) $fatal(1,"settings preview did not disable");
    @(negedge pixel_clk); ide=1;
    repeat(524) @(negedge pixel_clk);
    if(!fde || frgb!==24'hffffff) $fatal(1,"settings original white missing");
    press(1,2);
    repeat(6) @(negedge pixel_clk);
    if(filter_enable!==0 || frgb!==24'hffffff)
        $fatal(1,"settings preview enabled before frame boundary");
    frame();
    @(negedge pixel_clk); ide=1;
    repeat(524) @(negedge pixel_clk);
    if(!fde || frgb!==24'hfff0c0) $fatal(1,"settings preview did not re-enable");
    @(negedge pixel_clk); ide=0;
    press(1,23);
    if(home_events!=1 || preference!==1) $fatal(1,"long KEY4 edited pref or lost HOME");
    state_to(1,1);
    // HOME keeps the selected preference and renders the same warm preview.
    @(negedge pixel_clk); ide=1; rgb=24'hffffff;
    repeat(524) @(negedge pixel_clk);
    if(!fde || frgb!==24'hfff0c0) $fatal(1,"home warm preview missing");
    @(negedge pixel_clk); ide=0;
    press(0,2);
    if(preference!==1) $fatal(1,"HOME key edited preference");
    state_to(2,1);
    // Continuous lines include white OSD glyphs and first/last pixels.
    for(j=0;j<18;j=j+1) begin
        for(i=0;i<640;i=i+1) begin
            @(negedge pixel_clk); ide=1; rgb=24'hffffff;
        end
        @(negedge pixel_clk); ide=0;
        repeat(4) @(negedge pixel_clk);
    end
    if(white_checked==0) $fatal(1,"no final white OSD pixel exercised");
    for(i=0;i<16;i=i+1)
        state_to(4'(i), i==1 || i==2 || i==3 || i==4 || i==5 || i==7 || i==8);
    state_to(7,1);
    press(0,2);
    if(preference!==0) $fatal(1,"short KEY2 did not disable");
    repeat(6) @(negedge pixel_clk);
    frame();
    if(osd.eye_active!==0) $fatal(1,"off not committed");
    for(i=0;i<16;i=i+1) state_to(4'(i),0);
    // All 256 channel values, permuted independently; plus random samples.
    for(j=0;j<2;j=j+1) begin
        unit_enable=1'(j);
        for(i=0;i<4352;i=i+1) begin
            @(negedge pixel_clk);
            rgb=i<256 ? {8'(i),8'(255-i),8'((i*73)%256)} : $random;
            ide=(i<256) || ((i%7)!=0); ih=(i%5)==0; iv=(i%101)==0;
        end
    end
    @(negedge pixel_clk); rst=1; pixel_rst=1;
    #1;
    if({fh,fv,fde,frgb}!==0) $fatal(1,"pixel reset failed");
    repeat(3) @(negedge clk); rst=0;
    @(negedge pixel_clk); pixel_rst=0;
    repeat(8) @(negedge clk);
    if(preference!==1 || filter_enable!==0) $fatal(1,"reset recovery failed");
    $display("TEST_PASS eye comfort: %0d pixels, %0d warm OSD whites",checked,white_checked);
    $finish;
end
initial begin #5000000; $fatal(1,"watchdog"); end
endmodule
