`timescale 1ns/1ps

module tb_practice_scaling_banner;
reg clk=0, rst=1, boundary=0;
reg [3:0] state=0, target=0, image=12;
reg state_toggle=0, valid=0, transitioning=0;
wire [23:0] rgb;
reg video_de=0;
integer scan_x, scan_y, preview;
reg [23:0] expected_rgb;
always #5 clk=~clk;

video_effects_osd dut (
    .pixel_clk(clk),.pixel_rst(rst),.frame_boundary(boundary),
    .in_hs(1'b0),.in_vs(1'b0),.in_de(video_de),.in_rgb(24'hC0C0C0),
    .source_brightness(3'sd0),.source_contrast(2'd1),
    .source_osd_enable(1'b1),.source_subtitle_enable(1'b0),
    .source_control_toggle(1'b0),.source_ambient_enable(1'b0),
    .source_ambient_ready(1'b0),.source_zoom_preview_level(3'd2),
    .display_image_idx(image),.display_valid(valid),
    .transition_active(transitioning),.display_zoom_level(3'd2),
    .source_state_code(state),.source_wrong_bitmap(3'd0),
    .source_target_image_idx(target),.source_state_toggle(state_toggle),.state_ack_toggle(),
    .source_auto_play(1'b0),.source_volume_level(3'd4),
    .source_volume_toggle(1'b0),.source_speed_level(2'd2),
    .source_speed_toggle(1'b0),.voice_progress(9'd0),
    .voice_clip(2'd0),.voice_valid(1'b0),
    .source_eye_comfort_enable(1'b0),.eye_filter_enable(),
    .source_lesson_subtitle_active(1'b0),
    .source_lesson_subtitle_clip(2'd0),.source_lesson_subtitle_cue(5'd0),
    .source_lesson_subtitle_toggle(1'b0),
    .out_hs(),.out_vs(),.out_de(),.out_rgb(rgb)
);

task automatic frame;
begin
    @(negedge clk); boundary=1;
    @(negedge clk); boundary=0;
    #1;
end
endtask

task automatic publish(input [3:0] next_state,input [3:0] next_target);
begin
    @(negedge clk); state=next_state; target=next_target;
    state_toggle=~state_toggle;
    repeat(7) @(negedge clk);
    frame();
end
endtask

task automatic expect_label(input [3:0] card,input [135:0] expected);
reg [7:0] actual;
begin
    for(integer i=0;i<17;i=i+1) begin
        actual=dut.banner_char(i[4:0],card);
        if(actual !== expected[135-i*8-:8])
            $fatal(1,"label card=%0d cell=%0d actual=%h",card,i,actual);
    end
end
endtask

initial begin
    repeat(3) @(negedge clk); rst=0;
    expect_label(4'd3,"1280*960->640*480");
    expect_label(4'd8," 800*600->640*480");
    expect_label(4'd11," 320*240->640*480");
    publish(4'd3,4'd3);
    if(dut.banner_seen) $fatal(1,"banner before frame commit");
    image=3; valid=1; transitioning=1;
    repeat(3) frame();
    if(dut.banner_seen) $fatal(1,"banner during transition");
    transitioning=0; frame();
    if(!dut.banner_seen || dut.banner_frames!=0)
        $fatal(1,"banner did not start at committed image");
    force dut.pixel_x = 10'd368;
    force dut.pixel_y = 10'd0;
    #1;
    if(!dut.banner_region || dut.status_code != "1")
        $fatal(1,"first banner not visible in top-right row");
    force dut.pixel_x = 10'd512;
    #1;
    if(dut.status_code != ">")
        $fatal(1,"conversion arrow missing");
    // Check actual pipelined output across the complete joined row and below it.
    preview=$fopen("out/practice_banner_joined_row.ppm","w");
    $fwrite(preview,"P3\n640 32\n255\n");
    video_de=1;
    force dut.pixel_x=scan_x;
    force dut.pixel_y=scan_y;
    for(scan_y=0;scan_y<32;scan_y=scan_y+1) begin
        for(scan_x=0;scan_x<640;scan_x=scan_x+1) begin
            #1;
            if(dut.status_region !== (scan_y<16))
                $fatal(1,"disconnected row at x=%0d y=%0d",scan_x,scan_y);
            expected_rgb=scan_y<16 ?
                (dut.status_pixel ? 24'hFFFFFF : 24'h303030) : 24'hC0C0C0;
            repeat(3) @(negedge clk);
            #1;
            if(rgb !== expected_rgb)
                $fatal(1,"render x=%0d y=%0d got=%h expected=%h",scan_x,scan_y,rgb,expected_rgb);
            $fwrite(preview,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
        end
    end
    $fclose(preview);
    video_de=0;
    force dut.pixel_x=10'd368;
    force dut.pixel_y=10'd0;
    for(integer i=0;i<299;i=i+1) frame();
    if(dut.banner_frames!=299)
        $fatal(1,"banner expired early");
    frame();
    if(dut.banner_frames!=300 || dut.banner_region)
        $fatal(1,"banner did not expire at 300 frames");
    if(dut.status_region) $fatal(1,"expired banner background remains");
    force dut.pixel_x=10'd367;
    #1;
    if(!dut.status_region) $fatal(1,"expiry removed parameter row");
    release dut.pixel_x;
    release dut.pixel_y;
    repeat(3) frame();
    if(dut.banner_frames!=300) $fatal(1,"banner restarted after expiry");
    publish(4'd3,4'd8);
    if(dut.banner_eligible || dut.banner_region)
        $fatal(1,"old image announced as new question");
    image=8; valid=1; frame();
    if(!dut.banner_seen || dut.banner_image!=8)
        $fatal(1,"second pool banner missing");
    publish(4'd4,4'd8);
    frame();
    if(dut.banner_seen) $fatal(1,"banner leaked into feedback");
    publish(4'd5,4'd11);
    image=11; frame();
    if(!dut.banner_seen || dut.banner_image!=11)
        $fatal(1,"review banner missing");
    valid=0; frame();
    if(dut.banner_seen) $fatal(1,"invalid frame kept banner");
    $display("TEST_PASS tb_practice_scaling_banner");
    $finish;
end
endmodule
