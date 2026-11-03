`timescale 1ns/1ps
module tb_lesson_speed_audio;
reg audio_clk=0,pixel_clk=0,rst=1;
always #5 audio_clk=~audio_clk;
always #2 pixel_clk=~pixel_clk;
reg start=0,ending=0;
integer available=20000,consumed=0,accepted=0,cycles=0;
wire read,accept,bclk,lrck,dout,pcm_valid;
wire [23:0] left_pcm,right_pcm;
wire [23:0] wave_rgb;
integer first_cycle,last_cycle,delta,total,changes_normal;
integer previous_pcm,current_pcm,min_level,max_level;
integer stage=0;

wire empty = consumed >= available;
wire [7:0] head = consumed[0] ? 8'h60 : 8'h10;
hdmi_audio_tone_i2s_64fs dut (
 .I_mclk(audio_clk),.I_rst(rst),.I_lab_active(1'b0),
 .I_lab_frequency(2'd0),.I_lab_amplitude(2'd1),
 .I_lab_waveform(2'd0),.I_lab_muted(1'b0),.I_song_enable(1'b0),
 .I_lab_control_toggle(1'b0),.I_voice_volume(3'd4),
 .I_voice_volume_toggle(1'b0),
 .I_practice_prev_tone_toggle(1'b0),
 .I_practice_next_tone_toggle(1'b0),
 .I_boot_success_tone_toggle(1'b0),
 .I_voice_start_toggle(start),.I_voice_end_toggle(ending),
 .I_voice_stop_toggle(1'b0),.I_voice_clip_index(2'd0),
 .I_voice_fifo_data(head),.I_voice_fifo_speed(2'd3),
 .I_voice_fifo_valid(!empty),.I_voice_fifo_empty(empty),
 .I_voice_played_to_end(1'b0),.O_voice_fifo_read(read),
 .O_voice_sample_accept(accept),.O_voice_source_step(),
 .O_voice_subtitle_active(),
 .O_voice_subtitle_clip(),.O_voice_subtitle_cue(),
 .O_voice_subtitle_toggle(),.O_i2s_BCLK(bclk),
 .O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
I2S_receiver receiver (
 .I_clk(pixel_clk),.I_rst(rst),.I_i2s_BCLK(bclk),
 .I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),
 .O_audio_valid(pcm_valid),.O_audio_left_data(left_pcm),
 .O_audio_right_data(right_pcm));
audio_waveform_overlay wave (
 .pixel_clk(pixel_clk),.pixel_rst(rst),.frame_boundary(1'b0),
 .in_hs(1'b0),.in_vs(1'b0),.in_de(1'b0),.in_rgb(24'd0),
 .overlay_enable(1'b1),.theme_index(4'd0),
 .audio_valid(pcm_valid),.audio_sample(left_pcm),
 .out_hs(),.out_vs(),.out_de(),.out_rgb(wave_rgb));

always @(posedge audio_clk) begin
 cycles <= cycles+1;
 if (read && !empty) consumed <= consumed+1;
 if (accept) accepted <= accepted+1;
end

task automatic check_intervals(input integer low_cycles,
                               input integer high_cycles,
                               input integer expected_total);
 begin
  // The first observed interval can straddle narration fade-in.
  @(posedge accept);@(posedge accept);
  first_cycle=cycles;last_cycle=cycles;total=0;
  for(integer n=0;n<10;n=n+1)begin
   @(posedge accept);
   delta=cycles-last_cycle;
   if(delta!=low_cycles && delta!=high_cycles)
    $fatal(1,"bad speed interval %0d",delta);
   total=total+delta;last_cycle=cycles;
  end
  if(total!=expected_total)
   $fatal(1,"wrong total read cadence %0d expected %0d",total,expected_total);
 end
endtask

task automatic count_pcm_changes(output integer changes);
 begin
  changes=0;previous_pcm=-1;
  for(integer n=0;n<240;n=n+1)begin
   @(posedge pcm_valid);#1;
   if(left_pcm!==right_pcm)$fatal(1,"HDMI PCM channels differ");
   current_pcm=$signed(left_pcm);
   if(previous_pcm>=0 && current_pcm!=previous_pcm)changes=changes+1;
   previous_pcm=current_pcm;
  end
 end
endtask

initial begin
 repeat(6)@(negedge audio_clk);rst=0;
 repeat(20)@(negedge audio_clk);
 @(negedge audio_clk);start=1;
 stage=1;
 wait(dut.S_voice_active);
 stage=2;
 // Let the existing narration envelope reach full level.
 repeat(600)@(posedge pcm_valid);
 stage=3;
 check_intervals(768,768,7680);
 stage=4;
 count_pcm_changes(changes_normal);
 stage=5;
 check_intervals(768,768,7680);
 if(changes_normal<60)
  $fatal(1,"legacy narration PCM did not change normally");
 stage=6;
 min_level=255;max_level=0;
 for(integer n=0;n<256;n=n+1)begin
  if(wave.sample_memory[n]<min_level)min_level=wave.sample_memory[n];
  if(wave.sample_memory[n]>max_level)max_level=wave.sample_memory[n];
 end
 if(min_level==max_level)
  $fatal(1,"waveform overlay did not sample changing HDMI PCM");
 stage=7;
 @(negedge audio_clk);available=consumed;
 repeat(10)@(posedge pcm_valid);
 first_cycle=accepted;
 repeat(10)@(posedge pcm_valid);
 if(accepted!=first_cycle || dut.S_voice_sample_count!=accepted)
  $fatal(1,"FIFO underflow advanced consumed samples");
 @(negedge audio_clk);available=consumed+20;
 wait(accepted>first_cycle);
 stage=8;
 @(negedge audio_clk);available=consumed;ending=~ending;
 wait(!dut.S_voice_active);
 $display("TEST_PASS tb_lesson_speed_audio: legacy PCM stays 1x, waveform, underflow, EOF");
 $finish;
end
initial begin #10000000;$fatal(1,"speed audio timeout stage=%0d active=%b reads=%0d pcm=%b",stage,dut.S_voice_active,accepted,pcm_valid);end
endmodule
