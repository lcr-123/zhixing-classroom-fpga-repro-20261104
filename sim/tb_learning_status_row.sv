`timescale 1ns/1ps
module tb_learning_status_row;
reg clk=0,rst=1,fb=0,ide=0;
always #5 clk=~clk;
reg [3:0] state=2,image=0;
reg state_toggle=0,vol_toggle=0,speed_toggle=0;
reg [2:0] volume=4;
reg [1:0] speed=2;
reg [8:0] progress=128;
reg [1:0] clip=0;
reg valid=1;
reg subtitle=0;
wire oh,ov,od,wh,wv,wd;
wire [23:0] orgb,wrgb;
integer x,y,cx=0,cy=0,checked=0;
reg old_de=0;
reg [23:0] pixels[0:79][0:639];
video_effects_osd #(.FRAME_HEIGHT(80)) osd (
 .pixel_clk(clk),.pixel_rst(rst),.frame_boundary(fb),
 .in_hs(1'b0),.in_vs(1'b0),.in_de(ide),.in_rgb(24'h8090A0),
 .source_brightness(3'sd0),.source_contrast(2'd1),
 .source_osd_enable(1'b1),.source_subtitle_enable(1'b1),
 .source_control_toggle(1'b0),.source_zoom_preview_level(3'd2),
 .display_image_idx(image),.display_zoom_level(3'd2),
 .display_valid(1'b0),.transition_active(1'b0),.source_target_image_idx(4'd0),
 .source_wrong_bitmap(3'd0),.source_state_code(state),.source_state_toggle(state_toggle),
 .source_auto_play(1'b0),.source_eye_comfort_enable(1'b0),
 .source_volume_level(volume),.source_volume_toggle(vol_toggle),
 .source_speed_level(speed),.source_speed_toggle(speed_toggle),
 .voice_progress(progress),.voice_clip(clip),.voice_valid(valid),
 .source_lesson_subtitle_active(1'b1),.source_lesson_subtitle_clip(2'd0),
 .source_lesson_subtitle_cue(5'd0),.source_lesson_subtitle_toggle(subtitle),
 .eye_filter_enable(),.out_hs(oh),.out_vs(ov),.out_de(od),.out_rgb(orgb));
audio_waveform_overlay #(.FRAME_HEIGHT(80),.WAVE_TOP(32),.WAVE_HEIGHT(16)) wave (
 .pixel_clk(clk),.pixel_rst(rst),.frame_boundary(fb),
 .in_hs(oh),.in_vs(ov),.in_de(od),.in_rgb(orgb),
 .overlay_enable(state==2),.theme_index(image),
 .audio_valid(1'b0),.audio_sample(24'd0),
 .out_hs(wh),.out_vs(wv),.out_de(wd),.out_rgb(wrgb));
// Compare actual pre/post-waveform streams outside the panel, including all
// subtitle pixels. This catches a later stage accidentally painting over text.
reg [23:0] rgb_delay[0:2];
reg [2:0] de_delay=0;
always @(posedge clk) begin
 rgb_delay[0]<=orgb;rgb_delay[1]<=rgb_delay[0];rgb_delay[2]<=rgb_delay[1];
 de_delay<={de_delay[1:0],od};
end
always @(negedge clk) begin
 if(!rst && wd) begin
  pixels[cy][cx]=wrgb;
  if(cy<32 || cy>=48) begin
   if(!de_delay[2] || wrgb!==rgb_delay[2])
    $fatal(1,"wave overwrote OSD/subtitle at %0d,%0d",cx,cy);
   checked=checked+1;
  end
  cx=cx+1;
 end else if(old_de) begin cx=0;cy=cy+1;end
 old_de=wd;
end
function automatic [63:0] glyph(input integer c);
 case(c)
 0:glyph=64'h3C666E7666663C00;1:glyph=64'h1838181818187E00;
 2:glyph=64'h3C66060C30607E00;3:glyph=64'h3C66061C06663C00;
 4:glyph=64'h0C1C3C6C7E0C0C00;5:glyph=64'h7E607C0606663C00;
 6:glyph=64'h1C30607C66663C00;7:glyph=64'h7E66060C18181800;
 8:glyph=64'h3C66663C66663C00;9:glyph=64'h3C66663E060C3800;
  10:glyph=64'h62640C1830264600;
  11:glyph=0;12:glyph=64'h0000000000001818;
  13:glyph=64'h66663C183C666600;default:glyph=0;
 endcase
endfunction
task automatic check_cell(input integer cell_x,input integer code);
 reg [63:0] bitmap;reg [23:0] expected;
 begin
  bitmap=glyph(code);
  for(integer r=0;r<16;r=r+1) for(integer c=0;c<16;c=c+1) begin
   expected=bitmap[63-(r/2)*8-c/2]?24'hFFFFFF:24'h202428;
   if(pixels[r][cell_x*16+c]!==expected)
    $fatal(1,"status glyph/background cell=%0d code=%0d x=%0d y=%0d got=%h expected=%h",cell_x,code,c,r,pixels[r][cell_x*16+c],expected);
  end
 end
endtask
task automatic check_speed(input integer a,input integer b,input integer c);
 integer codes[0:4];reg [63:0] bitmap;reg [23:0] expected;
 begin
  codes[0]=a;codes[1]=12;codes[2]=b;codes[3]=c;codes[4]=13;
  for(integer idx=0;idx<5;idx=idx+1)
   for(integer r=0;r<16;r=r+1)for(integer col=0;col<16;col=col+1)begin
    bitmap=glyph(codes[idx]);
    expected=bitmap[63-(r/2)*8-col/2]?24'hFFFFFF:24'h202428;
    if(pixels[r][560+idx*16+col]!==expected)
     $fatal(1,"speed glyph cell=%0d x=%0d y=%0d got=%h expected=%h",
            idx,col,r,pixels[r][560+idx*16+col],expected);
   end
 end
endtask
task automatic boundary;
 begin @(negedge clk);fb=1;@(negedge clk);fb=0;end
endtask
task automatic frame;
 begin
 cx=0;cy=0;
 for(y=0;y<80;y=y+1) begin
  for(x=0;x<640;x=x+1) begin @(negedge clk);ide=1;end
  @(negedge clk);ide=0;repeat(8) @(negedge clk);
 end
 end
endtask
task automatic show_percent(input integer p);
 begin
 check_cell(31,p==100?1:11);
 check_cell(32,p>=10?(p%100)/10:11);check_cell(33,p%10);check_cell(34,10);
 end
endtask
initial begin
 repeat(3) @(negedge clk);rst=0;state_toggle=1;subtitle=1;
 repeat(8) @(negedge clk);boundary();frame();
 for(integer r=16;r<32;r=r+1)for(integer c=0;c<640;c=c+1)
  if(pixels[r][c]!==24'h8090A0)$fatal(1,"second status row was not released");
 check_cell(27,4);show_percent(50);
 check_speed(1,2,5);
 // Golden pixels from the original published caption glyph, independent of
 // the top status font. Caption 0 centers its first glyph at character 11.
 begin
  reg [255:0] original_first_glyph;
  original_first_glyph=256'h18201F7E345864883FF8018801883FF831803FFE3FFC07841D8C719801800000;
  for(integer r=0;r<16;r=r+1)for(integer c=0;c<16;c=c+1)
   if(pixels[64+r][176+c] !== (original_first_glyph[255-r*16-c]?24'hFFFFFF:24'h202428))
    $fatal(1,"original narration glyph disappeared or changed x=%0d y=%0d",c,r);
 end

 // Mutating the stable mailbox and progress during a frame must not change
 // the rendered fields until the next boundary.
 volume=1;vol_toggle=~vol_toggle;progress=256;
 speed=1;speed_toggle=~speed_toggle;
 repeat(8) @(negedge clk);
 if(osd.volume_active!==4 || osd.progress_active!==50 || osd.speed_active!==2)
  $fatal(1,"mid-frame field update");
 boundary();frame();check_cell(27,1);show_percent(100);check_speed(1,0,0);
 speed=0;speed_toggle=~speed_toggle;
 repeat(8)@(negedge clk);boundary();frame();check_speed(0,7,5);
 speed=3;speed_toggle=~speed_toggle;
 repeat(8)@(negedge clk);boundary();frame();check_speed(1,0,0);
 for(integer v=0;v<5;v=v+1)begin
  volume=v;vol_toggle=~vol_toggle;repeat(8) @(negedge clk);boundary();frame();check_cell(27,v);
 end
 // Exhaust all legal progress codes with an independent integer reference.
 for(integer n=0;n<=300;n=n+1)begin
  progress=n;boundary();
  if(osd.progress_active!==((n>256?256:n)*100/256))$fatal(1,"percent conversion %0d",n);
 end
 progress=26;boundary();frame();show_percent(10);
 valid=0;boundary();frame();show_percent(0);
 valid=1;clip=1;boundary();frame();show_percent(0);
 clip=0;image=1;boundary();frame();show_percent(0);
 image=0;progress=256;boundary();frame();show_percent(100);
 // Every other app state uses the compact OSD extent. SETTINGS keeps its
 // own eye-comfort cells, while the numeric audio area is entirely absent.
 for(integer s=0;s<16;s=s+1)if(s!=2)begin
  state=s;state_toggle=~state_toggle;repeat(8)@(negedge clk);boundary();frame();
  for(integer r=0;r<16;r=r+1)for(integer c=(s==7?432:368);c<640;c=c+1)
   if(pixels[r][c]!==24'h8090A0)$fatal(1,"learning status leaked into state %0d",s);
  for(integer r=16;r<32;r=r+1)for(integer c=560;c<640;c=c+1)
   if(pixels[r][c]!==24'h8090A0)$fatal(1,"speed row leaked into state %0d",s);
 end
 rst=1;repeat(3)@(negedge clk);
 if(osd.volume_active!==4 || osd.progress_active!==0 || osd.speed_active!==2)
  $fatal(1,"reset status");
 $display("TEST_PASS tb_learning_status_row: five levels, percent 0..100, all states, %0d untouched OSD/subtitle pixels",checked);
 $finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
