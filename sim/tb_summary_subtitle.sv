`timescale 1ns/1ps
module tb_summary_subtitle;
localparam APP_ST_BOOT_SELFTEST=0, APP_ST_SUMMARY=8;
reg clk=0,pixel_clk=0,rst_ref=1,pixel_rst=1,fb=0,de=0;
always #10 clk=~clk;
always #20 pixel_clk=~pixel_clk;
reg [3:0] learn_state=0,osd_state_mailbox_ref;
reg [2:0] learn_wrong_bitmap=0,osd_wrong_mailbox_ref;
reg [3:0] osd_target_image_mailbox_ref;
wire [3:0] app_desired_image_index = 4'd9;
reg osd_state_toggle_ref;
wire osd_state_ack_toggle;
reg [1:0] osd_state_ack_ref_sync;
wire od;
wire [23:0] rgb;
integer mask, pixels=0, expected_mask=0;
reg delayed_valid=0;
reg [23:0] delayed_rgb=0,next_rgb;
reg check_pixels=0;
integer n,col,row,pad;
reg [7:0] code;
`include "out/summary_subtitle/state_publish.vh"
video_effects_osd osd (
 .pixel_clk(pixel_clk),.pixel_rst(pixel_rst),.frame_boundary(fb),
 .in_hs(1'b0),.in_vs(1'b0),.in_de(de),.in_rgb(24'h406080),
 .source_brightness(3'sd0),.source_contrast(2'd1),
 .source_osd_enable(1'b0),.source_subtitle_enable(1'b1),
 .source_control_toggle(1'b0),.source_ambient_enable(1'b0),.source_ambient_ready(1'b0),
 .source_zoom_preview_level(3'd2),.display_image_idx(4'd9),.display_zoom_level(3'd2),
 .display_valid(1'b0),.transition_active(1'b0),
 .source_target_image_idx(osd_target_image_mailbox_ref),
 .source_state_code(osd_state_mailbox_ref),.source_wrong_bitmap(osd_wrong_mailbox_ref),
 .source_state_toggle(osd_state_toggle_ref),.source_auto_play(1'b0),
 .state_ack_toggle(osd_state_ack_toggle),
 .source_volume_level(3'd4),.source_volume_toggle(1'b0),
 .source_speed_level(2'd2),.source_speed_toggle(1'b0),
 .voice_progress(9'd0),.voice_clip(2'd0),.voice_valid(1'b0),
 .source_eye_comfort_enable(1'b0),.eye_filter_enable(),
 .source_lesson_subtitle_active(1'b0),.source_lesson_subtitle_clip(2'd0),
 .source_lesson_subtitle_cue(5'd0),.source_lesson_subtitle_toggle(1'b0),
 .out_hs(),.out_vs(),.out_de(od),.out_rgb(rgb));

function automatic [7:0] expected_code(input integer index,input integer bitmap);
begin
 expected_code=" ";
 if(bitmap!=0) case(index)
  0:expected_code=8'ha9;1:expected_code=8'haa;2:expected_code=":";
  3:expected_code=(bitmap&1)?"4":" ";
  5:expected_code=(bitmap&2)?"5":" ";
  7:expected_code=(bitmap&4)?"6":" ";
  9:expected_code=8'haf;10:expected_code=8'h9d;11:expected_code=8'ha9;
  12:expected_code=8'haa;13:expected_code=8'ha8;14:expected_code=8'hc7;
 endcase
 else case(index)
  0:expected_code=8'hc8;1:expected_code=8'ha9;2:expected_code=8'haa;
  4:expected_code=8'h95;5:expected_code=8'h96;6:expected_code=8'hcb;
  7:expected_code=8'ha8;8:expected_code=8'hc9;9:expected_code=8'hca;
 endcase
end
endfunction

// Compare final pixels with the retained combinational golden font. This
// also checks the generated native BRAM contents and two-stage alignment.
always @(posedge pixel_clk) if(check_pixels) begin
 next_rgb=24'h203040;
 pad=expected_mask!=0?8:48;
 n=(osd.pixel_x-pad)/16;col=(osd.pixel_x-pad)%16;row=osd.pixel_y-464;
 code=osd.pixel_x>=pad ? expected_code(n,expected_mask):" ";
 if(de && osd.font_row(code,row)&(16'h8000>>col)) next_rgb=24'hffd54a;
 #1;
 if(od!==delayed_valid) $fatal(1,"subtitle DE pipeline mismatch");
 if(delayed_valid) begin
   if(rgb!==delayed_rgb) $fatal(1,"summary pixel mask=%b got=%h expected=%h",expected_mask,rgb,delayed_rgb);
   pixels=pixels+1;
 end
 delayed_valid=de;delayed_rgb=next_rgb;
end

task automatic boundary;
begin @(negedge pixel_clk);fb=1;@(negedge pixel_clk);fb=0; end
endtask
task automatic render;
begin
 check_pixels=1;delayed_valid=0;
 for(integer y=0;y<16;y=y+1)begin
   @(negedge pixel_clk);osd.pixel_x=0;osd.pixel_y=464+y;osd.scroll_position=640;
   de=1;
   repeat(256) @(posedge pixel_clk);
   @(negedge pixel_clk);de=0;
   repeat(3) @(negedge pixel_clk);
 end
 check_pixels=0;
end
endtask

initial begin
 repeat(4) @(negedge pixel_clk);rst_ref=0;pixel_rst=0;
 for(mask=0;mask<8;mask=mask+1)begin
   @(negedge clk);learn_state=8;learn_wrong_bitmap=mask;
   repeat(10) @(negedge pixel_clk);
   if(osd.state_active==8 && osd.wrong_active!==expected_mask[2:0])
     $fatal(1,"wrong list changed inside frame");
   boundary();expected_mask=mask;
   if(osd.state_active!=8 || osd.wrong_active!==mask[2:0])
     $fatal(1,"summary state/list not committed together");
   render();
 end
 @(negedge clk);learn_state=1;
 repeat(10) @(negedge pixel_clk);
 if(osd.state_active!=8) $fatal(1,"HOME state changed before boundary");
 boundary();
 if(osd.state_active!=1) $fatal(1,"HOME did not clear summary context");
 @(negedge pixel_clk);pixel_rst=1;rst_ref=1;
 repeat(2) @(negedge pixel_clk);
 if(osd.wrong_active!=0 || osd.state_active!=0) $fatal(1,"reset retained wrong list");
 if(pixels!=32768) $fatal(1,"missing rendered subtitle pixels %0d",pixels);
 $display("TEST_PASS summary wrong subtitles: 8 bitmaps, real top mailbox, frame atomicity, 32768 golden BRAM pixels, HOME/reset");
 $finish;
end
initial begin #10000000;$fatal(1,"summary subtitle timeout");end
endmodule
