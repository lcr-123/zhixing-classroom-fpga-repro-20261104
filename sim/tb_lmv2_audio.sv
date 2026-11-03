`timescale 1ns/1ps
module tb_lmv2_audio;
reg clk=0,pixel_clk=0,ref_clk=0,rst=1,start=0,ending=0;
integer consumed=0,accepted=0;
integer i,min_wave,max_wave;
integer mclk_cycles=0,last_lrck_cycle=-1,lrck_edges=0;
wire read,accept,bclk,lrck,dout;
wire pcm_valid;
wire [23:0] left_pcm,right_pcm,wave_rgb;
wire [1:0] source_step;
wire played_to_end,subtitle_active,auto_next;
integer auto_count=0;
wire [1:0] tag = consumed < 100 ? 0 : consumed < 200 ? 1 : 2;
wire [7:0] pcm = consumed[0] ? 8'h30 : 8'hd0;
always #5 clk=~clk;
always #2 pixel_clk=~pixel_clk;
always #7 ref_clk=~ref_clk;
hdmi_audio_tone_i2s_64fs dut(
 .I_mclk(clk),.I_rst(rst),.I_lab_active(1'b0),.I_lab_frequency(2'd0),
 .I_lab_amplitude(2'd0),.I_lab_waveform(2'd0),.I_lab_muted(1'b0),
 .I_song_enable(1'b0),.I_lab_control_toggle(1'b0),
 .I_voice_volume(3'd4),.I_voice_volume_toggle(1'b0),
 .I_practice_prev_tone_toggle(1'b0),.I_practice_next_tone_toggle(1'b0),
 .I_boot_success_tone_toggle(1'b0),
 .I_voice_start_toggle(start),.I_voice_end_toggle(ending),
 .I_voice_stop_toggle(1'b0),.I_voice_clip_index(2'd0),
 .I_voice_fifo_data(pcm),.I_voice_fifo_speed(tag),
 .I_voice_fifo_valid(consumed<300),.I_voice_fifo_empty(consumed>=300),
 .I_voice_played_to_end(played_to_end),
 .O_voice_fifo_read(read),.O_voice_sample_accept(accept),
 .O_voice_source_step(source_step),.O_voice_subtitle_active(subtitle_active),
 .O_voice_subtitle_clip(),.O_voice_subtitle_cue(),
 .O_voice_subtitle_toggle(),.O_i2s_BCLK(bclk),
 .O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
lesson_audio_status status(
 .audio_clk(clk),.audio_rst(rst),.source_start_toggle(start),
 .source_stop_toggle(1'b0),.source_total(32'd300),.source_clip(2'd0),
 .consume(accept),.consume_step(source_step),
 .played_to_end(played_to_end),.pixel_clk(pixel_clk),
 .pixel_rst(rst),.frame_boundary(1'b0),
 .progress(),.clip(),.valid());
lesson_auto_advance advance(
 .clk(ref_clk),.rst(rst),.app_state(4'd2),.page_index(3'd0),
 .voice_active_async(subtitle_active),
 .voice_complete_async(played_to_end),.auto_next_pulse(auto_next));
always @(posedge ref_clk)begin
 if(auto_next)begin
  if(subtitle_active)$fatal(10,"auto page advanced during audible narration");
  auto_count<=auto_count+1;
 end
end
I2S_receiver receiver(
 .I_clk(pixel_clk),.I_rst(rst),.I_i2s_BCLK(bclk),
 .I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),.O_audio_valid(pcm_valid),
 .O_audio_left_data(left_pcm),.O_audio_right_data(right_pcm));
audio_waveform_overlay wave(
 .pixel_clk(pixel_clk),.pixel_rst(rst),.frame_boundary(1'b0),
 .in_hs(1'b0),.in_vs(1'b0),.in_de(1'b0),.in_rgb(24'd0),
 .overlay_enable(1'b1),.theme_index(4'd0),
 .audio_valid(pcm_valid),.audio_sample(left_pcm),
 .out_hs(),.out_vs(),.out_de(),.out_rgb(wave_rgb));
always @(posedge pixel_clk) begin
 if(pcm_valid && left_pcm!==right_pcm)
  $fatal(6,"I2S PCM channels differ");
end
always @(posedge clk) begin
 mclk_cycles<=mclk_cycles+1;
 if(read && consumed<300)consumed<=consumed+1;
 if(accept)accepted<=accepted+1;
end
always @(posedge lrck) begin
 if(!rst)begin
  if(last_lrck_cycle>=0 && mclk_cycles-last_lrck_cycle!=256)
   $fatal(8,"I2S frame period changed: %0d",mclk_cycles-last_lrck_cycle);
  last_lrck_cycle=mclk_cycles;
  lrck_edges=lrck_edges+1;
 end
end
initial begin
 repeat(8)@(negedge clk);rst=0;
 repeat(15)@(negedge clk);start=1;
 wait(dut.S_voice_active);
 wait(accepted==100);repeat(2)@(negedge clk);
 if(!dut.S_voice_active || dut.S_voice_sample_count!=75)
  $fatal(1,"slow audible position %0d",dut.S_voice_sample_count);
 wait(accepted==200);repeat(2)@(negedge clk);
 if(!dut.S_voice_active || dut.S_voice_sample_count!=175)
  $fatal(2,"normal audible position %0d",dut.S_voice_sample_count);
 wait(accepted==300);repeat(2)@(negedge clk);
 if(!dut.S_voice_active || dut.S_voice_sample_count!=300)
  $fatal(3,"fast audible position %0d",dut.S_voice_sample_count);
 if(lrck_edges<800)
  $fatal(9,"too few 48 kHz I2S frames");
 repeat(8)@(negedge clk);
 if(dut.S_voice_sample_count!=300)
  $fatal(4,"empty FIFO advanced audible position");
 min_wave=255;max_wave=0;
 for(i=0;i<256;i=i+1)begin
  if(wave.sample_memory[i]<min_wave)min_wave=wave.sample_memory[i];
  if(wave.sample_memory[i]>max_wave)max_wave=wave.sample_memory[i];
 end
 if(min_wave==max_wave)
  $fatal(7,"LMV2 waveform did not sample HDMI PCM");
 wait(played_to_end);
 wait(!dut.S_voice_active);
 wait(auto_count==1);
 repeat(6)@(negedge clk);
 if(auto_count!=1)$fatal(11,"automatic page advanced more than once");
 $display("TEST_PASS tb_lmv2_audio: 16k PCM, source position, audible EOF, automatic page");
 $finish;
end
initial begin #4000000;$fatal(5,"LMV2 audio timeout count=%0d",accepted);end
endmodule
