`timescale 1ns/1ps
module tb_lmv2_fifo_tags;
reg sd_clk=0,audio_clk=0,rst=1,we=0,re=0;
reg [9:0] input_word=0;
wire [9:0] output_word;
wire valid,full_flag,empty_flag;
wire [9:0] wrusedw,rdusedw;
integer i;
always #5 sd_clk=~sd_clk;
always #7 audio_clk=~audio_clk;
wfifo_32_32_512 #(
 .DATA_WIDTH_W(10),.DATA_WIDTH_R(10),
 .ADDR_WIDTH_W(10),.ADDR_WIDTH_R(10),
 .AL_FULL_NUM(1000),.AL_EMPTY_NUM(2)
) dut(
 .rst(rst),.clkw(sd_clk),.clkr(audio_clk),.we(we),.di(input_word),
 .re(re),.dout(output_word),.valid(valid),.full_flag(full_flag),
 .empty_flag(empty_flag),.afull(),.aempty(),
 .wrusedw(wrusedw),.rdusedw(rdusedw));

initial begin
 repeat(8)@(negedge sd_clk);rst=0;
 repeat(8)@(negedge sd_clk);
 for(i=0;i<36;i=i+1)begin
  @(negedge sd_clk);
  input_word={2'(i%3),8'(i+17)};
  we=1;
 end
 @(negedge sd_clk);we=0;
 wait(rdusedw>=36);
 for(i=0;i<36;i=i+1)begin
  @(negedge audio_clk);
  if(!valid || output_word!=={2'(i%3),8'(i+17)})
   $fatal(1,"10-bit FIFO tag/data mismatch at %0d: %h",i,output_word);
  re=1;
  @(negedge audio_clk);re=0;
 end
 repeat(8)@(negedge audio_clk);
 if(!empty_flag)$fatal(2,"FIFO did not drain");
 $display("TEST_PASS tb_lmv2_fifo_tags: vendor async FIFO preserves 2-bit speed tags");
 $finish;
end
initial begin #100000;$fatal(3,"FIFO tag timeout");end
endmodule
