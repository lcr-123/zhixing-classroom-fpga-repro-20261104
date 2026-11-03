`timescale 1ns/1ps
// Exercise the actual top-level publisher and actual OSD receiver at 50/25 MHz.
// The legacy publisher is retained solely as a negative control.
module osd_mailbox_case #(parameter PHASE=0, LEGACY=0)(output reg done=0, lost=0);
localparam APP_ST_BOOT_SELFTEST=0, APP_ST_SUMMARY=8;
reg clk=0,pixel_clk=0,rst_ref=1,pixel_rst=1,fb=0;
always #10 clk=~clk;
initial begin #(PHASE+1); forever #20 pixel_clk=~pixel_clk; end
reg [3:0] learn_state=0,app_desired_image_index=0,osd_state_mailbox_ref;
reg [2:0] learn_wrong_bitmap=0,osd_wrong_mailbox_ref;
reg [3:0] osd_target_image_mailbox_ref;
reg osd_state_toggle_ref;
wire osd_state_ack_toggle;
reg [1:0] osd_state_ack_ref_sync;
generate if(!LEGACY) begin: production
`include "out/osd_state_mailbox/state_publish.vh"
end else begin: negative_control
always @(posedge clk or posedge rst_ref) begin
 if(rst_ref) begin
  osd_state_mailbox_ref<=0;osd_wrong_mailbox_ref<=0;
  osd_target_image_mailbox_ref<=0;osd_state_toggle_ref<=0;
 end else if(learn_state!=osd_state_mailbox_ref ||
             app_desired_image_index!=osd_target_image_mailbox_ref ||
             (learn_state==APP_ST_SUMMARY && learn_wrong_bitmap!=osd_wrong_mailbox_ref)) begin
  osd_state_mailbox_ref<=learn_state;osd_wrong_mailbox_ref<=learn_wrong_bitmap;
  osd_target_image_mailbox_ref<=app_desired_image_index;
  osd_state_toggle_ref<=~osd_state_toggle_ref;
 end
end
end endgenerate

video_effects_osd osd (
 .pixel_clk(pixel_clk),.pixel_rst(pixel_rst),.frame_boundary(fb),
 .in_hs(1'b0),.in_vs(1'b0),.in_de(1'b0),.in_rgb(24'd0),
 .source_brightness(3'sd0),.source_contrast(2'd1),
 .source_osd_enable(1'b1),.source_subtitle_enable(1'b1),
 .source_control_toggle(1'b0),.source_ambient_enable(1'b0),.source_ambient_ready(1'b0),
 .source_zoom_preview_level(3'd2),.display_image_idx(4'd9),.display_zoom_level(3'd2),
 .display_valid(1'b1),.transition_active(1'b0),
 .source_target_image_idx(osd_target_image_mailbox_ref),
 .source_state_code(osd_state_mailbox_ref),.source_wrong_bitmap(osd_wrong_mailbox_ref),
 .source_state_toggle(osd_state_toggle_ref),.state_ack_toggle(osd_state_ack_toggle),
 .source_auto_play(1'b0),.source_volume_level(3'd4),.source_volume_toggle(1'b0),
 .source_speed_level(2'd2),.source_speed_toggle(1'b0),
 .voice_progress(9'd0),.voice_clip(2'd0),.voice_valid(1'b0),
 .source_eye_comfort_enable(1'b0),.eye_filter_enable(),
 .source_lesson_subtitle_active(1'b0),.source_lesson_subtitle_clip(2'd0),
 .source_lesson_subtitle_cue(5'd0),.source_lesson_subtitle_toggle(1'b0),
 .out_hs(),.out_vs(),.out_de(),.out_rgb());

reg [10:0] previous_payload;
reg previous_toggle,previous_busy=0;
always @(negedge clk) begin
 if(!LEGACY && !rst_ref && previous_busy &&
    ({osd_target_image_mailbox_ref,osd_wrong_mailbox_ref,osd_state_mailbox_ref}!==previous_payload ||
     osd_state_toggle_ref!==previous_toggle))
  $fatal(1,"busy payload changed phase=%0d",PHASE);
 previous_payload={osd_target_image_mailbox_ref,osd_wrong_mailbox_ref,osd_state_mailbox_ref};
 previous_toggle=osd_state_toggle_ref;
 previous_busy=!rst_ref && osd_state_ack_ref_sync[1]!=osd_state_toggle_ref;
end

task automatic settle_commit(input [3:0] state_code,image,input [2:0] wrong);
begin
 repeat(40) @(negedge clk);
 if(!LEGACY && osd.state_pending!=={image,wrong,state_code})
  $fatal(1,"latest pending lost phase=%0d pending=%h",PHASE,osd.state_pending);
 @(negedge pixel_clk);fb=1;
 @(negedge pixel_clk);fb=0;
 if({osd.target_image_active,osd.wrong_active,osd.state_active}!=={image,wrong,state_code}) begin
  if(LEGACY) lost=1;
  else $fatal(1,"atomic commit mismatch phase=%0d",PHASE);
 end
end endtask

initial begin
 repeat(5) @(negedge clk);rst_ref=0;pixel_rst=0;
 // Entry state changes one source cycle before the random question selector.
 @(negedge clk);learn_state=4;app_desired_image_index=3;
 @(negedge clk);app_desired_image_index=9;
 settle_commit(4,9,0);
 if(!LEGACY) begin
  // Source changes every cycle while the receiver is busy: latest wins.
  for(integer i=0;i<20;i=i+1) begin
   @(negedge clk);learn_state=8;learn_wrong_bitmap=i%8;app_desired_image_index=i%12;
  end
  settle_commit(8,7,3);
  // No frame boundary: active state must retain the previous complete frame.
  @(negedge clk);learn_state=1;app_desired_image_index=12;
  repeat(40) @(negedge clk);
  if({osd.target_image_active,osd.wrong_active,osd.state_active}!=={4'd7,3'd3,4'd8})
   $fatal(1,"mid-frame state changed phase=%0d",PHASE);
  settle_commit(1,12,3);
  // Reset during an outstanding transfer, then a new complete transaction.
  @(negedge clk);learn_state=4;app_desired_image_index=6;
  @(negedge clk);rst_ref=1;pixel_rst=1;learn_state=0;app_desired_image_index=0;learn_wrong_bitmap=0;
  repeat(5) @(negedge clk);rst_ref=0;pixel_rst=0;
  @(negedge clk);learn_state=9;app_desired_image_index=10;learn_wrong_bitmap=5;
  settle_commit(9,10,5);
 end
 done=1;
end
endmodule

module tb_osd_state_mailbox;
wire [7:0] done_new,done_old,lost_new,lost_old;
genvar p;
generate for(p=0;p<8;p=p+1) begin: phases
 osd_mailbox_case #(.PHASE(p*5)) corrected(done_new[p],lost_new[p]);
 osd_mailbox_case #(.PHASE(p*5),.LEGACY(1)) legacy(done_old[p],lost_old[p]);
end endgenerate
initial begin
 wait((&done_new) && (&done_old));
 if(!(|lost_old)) $fatal(1,"negative control did not reproduce toggle cancellation");
 $display("EXPECTED_LEGACY_LOSS phase_mask=%b",lost_old);
 $display("TEST_PASS OSD ACK mailbox: 8 clock phases, adjacent updates, busy coalescing, atomic frame, reset");
 $finish;
end
initial begin #100000; $fatal(1,"mailbox timeout"); end
endmodule
