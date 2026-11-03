`timescale 1ns/1ps
module tb_lmv2_voice_reader;
reg clk=0,rst=1,start=0,stop=0,valid=0,ending=0,error=0;
reg [7:0] data=0;
reg [1:0] speed=2;
reg toggle=0;
reg bad_block=0;
wire read,busy,begin_pulse,end_pulse,error_pulse,recover,pcm_valid;
wire [31:0] addr,total;
wire [7:0] pcm;
wire [1:0] pcm_speed;
reg [7:0] captured[0:15];
reg [1:0] tags[0:15];
integer count=0,starts=0,ends=0,errors=0;
always #5 clk=~clk;

lesson_voice_reader #(.SD_PROGRESS_TIMEOUT_CYCLES(100)) dut(
 .clk(clk),.rst(rst),.start(start),.stop(stop),.bmp_sector(32'd100),
 .voice_byte_offset(32'd500),.expected_page(2'd1),.buffer_ready(1'b1),
 .speed_level(speed),.speed_toggle(toggle),.ready(),.busy(busy),
 .voice_start_pulse(begin_pulse),.voice_end_pulse(end_pulse),
 .voice_error_pulse(error_pulse),.sd_recover_pulse(recover),
 .voice_page(),.voice_sample_total(total),.voice_data_valid(pcm_valid),
 .voice_data(pcm),.voice_data_speed(pcm_speed),.sd_sec_read(read),
 .sd_sec_read_addr(addr),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),
 .sd_sec_read_error(error));

always @(posedge clk) begin
 if(pcm_valid) begin
  captured[count]<=pcm;tags[count]<=pcm_speed;count<=count+1;
 end
 if(begin_pulse)starts<=starts+1;
 if(end_pulse)ends<=ends+1;
 if(error_pulse)errors<=errors+1;
end

function automatic [7:0] media(input integer index);
 begin
  case(index)
   0:media="L";1:media="M";2:media="V";3:media="2";
   4:media=1;5:media=2;6:media=8'h80;7:media=8'h3e;
   8:media=8;9:media=0;10:media=0;11:media=0;
   // One source block: span 4, lengths 5/4/3.
   16:media=4;17:media=0;18:media=5;19:media=0;
   20:media=4;21:media=0;22:media=bad_block ? 0 : 3;23:media=0;
   24:media=8'ha0;25:media=8'ha1;26:media=8'ha2;
   27:media=8'ha3;28:media=8'ha4;
   29:media=8'hb0;30:media=8'hb1;31:media=8'hb2;32:media=8'hb3;
   33:media=8'hc0;34:media=8'hc1;35:media=8'hc2;
   // Second block selects fast track after a mailbox update.
   36:media=4;37:media=0;38:media=5;39:media=0;
   40:media=4;41:media=0;42:media=3;43:media=0;
   44:media=8'hd0;45:media=8'hd1;46:media=8'hd2;
   47:media=8'hd3;48:media=8'hd4;
   49:media=8'he0;50:media=8'he1;51:media=8'he2;52:media=8'he3;
   53:media=8'hf0;54:media=8'hf1;55:media=8'hf2;
   default:media=0;
  endcase
 end
endfunction

integer i,sector,relative;
initial begin
 repeat(5)@(negedge clk);rst=0;
 @(negedge clk);start=1;
 @(negedge clk);start=0;
 for(sector=0;sector<2;sector=sector+1)begin
  wait(read);
  for(i=0;i<512;i=i+1)begin
   relative=i+(sector==0 ? -500 : 12);
   @(negedge clk);data=media(relative);valid=1;
   @(negedge clk);valid=0;
   if(relative==25)begin
    speed=1;toggle=~toggle;
   end
  end
  @(negedge clk);ending=1;
  @(negedge clk);ending=0;
 end
 wait(!busy);repeat(4)@(negedge clk);
 if(total!=8 || starts!=1 || ends!=1 || errors!=0 || count!=7)
  $fatal(1,"LMV2 lifecycle total=%0d starts=%0d ends=%0d errors=%0d count=%0d",
   total,starts,ends,errors,count);
 for(i=0;i<3;i=i+1)
  if(captured[i] !== (8'hc0+i) || tags[i] !== 2)
   $fatal(2,"default 1.25x track mismatch at %0d data=%h tag=%0d",i,captured[i],tags[i]);
 for(i=0;i<4;i=i+1)
  if(captured[i+3] !== (8'he0+i) || tags[i+3] !== 1)
   $fatal(3,"updated 1.00x track mismatch at %0d data=%h tag=%0d",i,captured[i+3],tags[i+3]);

 bad_block=1;
 @(negedge clk);start=1;
 @(negedge clk);start=0;
 for(sector=0;sector<2;sector=sector+1)begin
  wait(read);
  for(i=0;i<512;i=i+1)begin
   relative=i+(sector==0 ? -500 : 12);
   @(negedge clk);data=media(relative);valid=1;
   @(negedge clk);valid=0;
  end
  @(negedge clk);ending=1;
  @(negedge clk);ending=0;
 end
 wait(!busy);repeat(4)@(negedge clk);
 if(errors!=1 || count!=7)
  $fatal(4,"malformed block was accepted errors=%0d count=%0d",errors,count);
 $display("TEST_PASS tb_lmv2_voice_reader: aligned switch, tags, EOF, malformed block");
 $finish;
end
initial begin #50000;$fatal(4,"LMV2 reader timeout");end
endmodule
