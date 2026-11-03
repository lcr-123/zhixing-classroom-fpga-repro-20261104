`timescale 1ns/1ps
module tb_lmv2_real_package_reader;
reg clk=0,rst=1,start=0,valid=0,ending=0;
reg [7:0] data=0;
reg [1:0] page_index=0;
reg [1:0] speed_level=2;
reg speed_toggle=0;
wire read,busy,start_pulse,end_pulse,error_pulse,recover,pcm_valid;
wire [31:0] addr,total;
wire [7:0] pcm;
wire [1:0] pcm_speed;
reg [7:0] sector_data[0:511];
integer pcm_count=0,start_count=0,end_count=0,error_count=0;
integer page,mode,fd,seek_status,loaded,sector,byte_index,expected,source_total;
reg [31:0] sector_addr;
string filename;
always #5 clk=~clk;

lesson_voice_reader #(.SD_PROGRESS_TIMEOUT_CYCLES(1000)) dut(
 .clk(clk),.rst(rst),.start(start),.stop(1'b0),
 .bmp_sector(32'd100),.voice_byte_offset(32'd921654),
 .expected_page(page_index),.buffer_ready(1'b1),
 .speed_level(speed_level),.speed_toggle(speed_toggle),
 .ready(),.busy(busy),.voice_start_pulse(start_pulse),
 .voice_end_pulse(end_pulse),.voice_error_pulse(error_pulse),
 .sd_recover_pulse(recover),.voice_page(),.voice_sample_total(total),
 .voice_data_valid(pcm_valid),.voice_data(pcm),
 .voice_data_speed(pcm_speed),.sd_sec_read(read),
 .sd_sec_read_addr(addr),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),
 .sd_sec_read_error(1'b0));

always @(posedge clk) begin
 if(!rst)begin
  if(pcm_valid)begin
   if(pcm_speed!==speed_level)$fatal(1,"wrong PCM track tag got=%0d expected=%0d current=%0d block=%0d",pcm_speed,speed_level,dut.speed_current,dut.block_speed);
   pcm_count<=pcm_count+1;
  end
  if(start_pulse)start_count<=start_count+1;
  if(end_pulse)end_count<=end_count+1;
  if(error_pulse)begin
   error_count<=error_count+1;
   $fatal(2,"real LMV2 page %0d rejected at sector %0d block_phase=%b header=%0d track=%0d index=%0d span=%0d remain=%0d lengths=%0d/%0d/%0d",
    page,sector,dut.block_header_phase,dut.block_header_index,
    dut.block_track,dut.track_index,dut.block_source_samples,
    dut.source_remaining,dut.track_length0,dut.track_length1,
    dut.track_length2);
  end
 end
end

initial begin
 for(page=1;page<=3;page=page+1)begin
  case(page)
   1:filename="artifacts/english_nature_pitch_preserving_audio_v2/tf_card_ready_pitch_preserving/01.bmp";
   2:filename="artifacts/english_nature_pitch_preserving_audio_v2/tf_card_ready_pitch_preserving/02.bmp";
   3:filename="artifacts/english_nature_pitch_preserving_audio_v2/tf_card_ready_pitch_preserving/03.bmp";
  endcase
  for(mode=0;mode<3;mode=mode+1)begin
   case(page)
    1:begin source_total=414176;case(mode)0:expected=552235;1:expected=414176;2:expected=331341;endcase end
    2:begin source_total=432032;case(mode)0:expected=576043;1:expected=432032;2:expected=345626;endcase end
    3:begin source_total=425984;case(mode)0:expected=567979;1:expected=425984;2:expected=340787;endcase end
   endcase
   fd=$fopen(filename,"rb");
   if(!fd)$fatal(1,"cannot open %s",filename);
   @(negedge clk);rst=1;page_index=page-1;
   speed_level=mode;speed_toggle=0;
   pcm_count=0;start_count=0;end_count=0;error_count=0;
   repeat(4)@(negedge clk);rst=0;
   // Always publish the selected mode.  Mode 1 used to rely on the old
   // 1.00x reset value; the production default is now 1.25x.
   begin @(negedge clk);speed_toggle=1; end
   repeat(8)@(negedge clk);
   @(negedge clk);start=1;
   @(negedge clk);start=0;
   sector=0;
   while(busy && sector<5000)begin
    wait(read);
    sector_addr=addr;
    seek_status=$fseek(fd,(sector_addr-100)*512,0);
    if(seek_status!=0)$fatal(4,"seek failed page %0d sector %0d",page,sector);
    for(byte_index=0;byte_index<512;byte_index=byte_index+1)
     sector_data[byte_index]=0;
    loaded=$fread(sector_data,fd);
    for(byte_index=0;byte_index<512;byte_index=byte_index+1)begin
     @(negedge clk);data=sector_data[byte_index];valid=1;
    end
    @(negedge clk);valid=0;ending=1;
    @(negedge clk);ending=0;
    sector=sector+1;
   end
   repeat(4)@(negedge clk);
   if(busy || start_count!=1 || end_count!=1 || error_count!=0 ||
      total!=source_total || pcm_count!=expected)
    $fatal(5,"page=%0d speed=%0d sectors=%0d busy=%b start/end/error=%0d/%0d/%0d total=%0d PCM=%0d expected=%0d",
     page,mode,sector,busy,start_count,end_count,error_count,total,pcm_count,expected);
   $display("REAL_PACKAGE_PASS page=%0d speed=%0d sectors=%0d samples=%0d",page,mode,sector,pcm_count);
   $fclose(fd);
  end
 end
 $display("TEST_PASS tb_lmv2_real_package_reader");
 $finish;
end
initial begin #600000000;$fatal(6,"full LMV2 package timeout page=%0d sector=%0d",page,sector);end
endmodule
