`timescale 1ns/1ps
module tb_practice_page_display;
reg clk=0,rst=1,fb=0,de=0;
always #5 clk=~clk;
reg [3:0] image=0,state=3;
reg state_toggle=0,start=0;
reg [15:0] entropy=0;
wire selected,fault;
wire [3:0] q0,q1,q2;
wire od;
wire [23:0] rgb;
integer xout=0,yout=0,pixels=0;
reg old_de=0;
reg [8:0] seen=0;
reg [63:0] expected_digit;
reg [3:0] expected_page;

random_three_question_selector selector (
 .clk(clk),.rst(rst),.session_start(start),.entropy_counter(entropy),
 .vocabulary_count(2'd3),.sentence_count(2'd3),.question_count(2'd3),
 .selection_valid(selected),.selection_fault(fault),
 .question_image0(q0),.question_image1(q1),.question_image2(q2));

video_effects_osd #(.FRAME_WIDTH(64),.FRAME_HEIGHT(32)) dut (
 .pixel_clk(clk),.pixel_rst(rst),.frame_boundary(fb),
 .in_hs(1'b0),.in_vs(1'b0),.in_de(de),.in_rgb(24'h8090A0),
 .source_brightness(3'sd0),.source_contrast(2'd1),
 .source_osd_enable(1'b1),.source_subtitle_enable(1'b0),
 .source_control_toggle(1'b0),.source_zoom_preview_level(3'd2),
 .display_image_idx(image),.display_zoom_level(3'd2),
 .display_valid(1'b0),.transition_active(1'b0),.source_target_image_idx(4'd0),
 .source_wrong_bitmap(3'd0),.source_state_code(state),.source_state_toggle(state_toggle),
 .source_auto_play(1'b0),.source_volume_level(3'd4),
 .source_volume_toggle(1'b0),.source_speed_level(2'd1),
 .source_speed_toggle(1'b0),.voice_progress(9'd0),
 .voice_clip(2'd0),.voice_valid(1'b0),.source_eye_comfort_enable(1'b0),
 .eye_filter_enable(),.source_lesson_subtitle_active(1'b0),
 .source_lesson_subtitle_clip(2'd0),.source_lesson_subtitle_cue(5'd0),
 .source_lesson_subtitle_toggle(1'b0),
 .out_hs(),.out_vs(),.out_de(od),.out_rgb(rgb));

function automatic [63:0] digit(input integer n);
 case(n)
 4:digit=64'h0C1C3C6C7E0C0C00;
 5:digit=64'h7E607C0606663C00;
 6:digit=64'h1C30607C66663C00;
 default:digit=0;
 endcase
endfunction

always @(negedge clk) begin
 if(!rst && od) begin
  if(xout>=48 && xout<64) begin
   if(rgb !== (expected_digit[63-(yout/2)*8-(xout-48)/2] ?
                24'hFFFFFF:24'h202428))
    $fatal(1,"practice label pixel state=%0d file=%0d page=%0d x=%0d y=%0d",
           state,image,expected_page,xout,yout);
   pixels=pixels+1;
  end
  xout=xout+1;
 end else if(old_de) begin xout=0;yout=yout+1;end
 old_de=od;
end

task automatic boundary;
 begin @(negedge clk);fb=1;@(negedge clk);fb=0;end
endtask

task automatic render(input [3:0] file_index,input integer page);
 begin
  image=file_index;expected_page=page;expected_digit=digit(page);
  boundary();xout=0;yout=0;
  for(integer y=0;y<16;y=y+1)begin
   for(integer x=0;x<64;x=x+1)begin @(negedge clk);de=1;end
   @(negedge clk);de=0;repeat(8)@(negedge clk);
  end
 end
endtask

initial begin
 repeat(3)@(negedge clk);rst=0;
 // Exhaust every card in practice, answer feedback and wrong-question review.
 for(integer s=3;s<=5;s=s+1)begin
  state=s;state_toggle=~state_toggle;repeat(8)@(negedge clk);
  for(integer i=3;i<12;i=i+1)render(i,4+(i-3)/3);
 end
 // All other application states retain their original physical image labels;
 // out-of-range images also retain the existing bounded four-bit behavior.
 for(integer s=0;s<16;s=s+1)begin
  state=s;state_toggle=~state_toggle;repeat(8)@(negedge clk);boundary();
  for(integer i=0;i<16;i=i+1)begin
   image=i;#1;
   if(dut.status_image_idx !==
      ((s>=3 && s<=5 && i>=3 && i<12)?(3+(i-3)/3):i))
    $fatal(1,"state/invalid isolation state=%0d image=%0d",s,i);
  end
 end
 state=3;state_toggle=~state_toggle;repeat(8)@(negedge clk);boundary();
 // Exercise the actual random selector. The physical card and selection stay
 // independent of the displayed page; different sessions must cover all cards.
 for(integer session=0;session<32;session=session+1)begin
  entropy=session*16'h09E3+16'h1234;
  @(negedge clk);start=1;@(negedge clk);start=0;#1;
  if(!selected || fault || q0<3 || q0>5 || q1<6 || q1>8 || q2<9 || q2>11)
   $fatal(1,"random selection invalid");
  seen[q0-3]=1;seen[q1-3]=1;seen[q2-3]=1;
  render(q0,4);render(q1,5);render(q2,6);
 end
 if(seen!==9'h1FF)$fatal(1,"random coverage incomplete %h",seen);
 $display("TEST_PASS tb_practice_page_display: 9 random cards, 32 sessions, states/invalid isolation, %0d golden page pixels",pixels);
 $finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
