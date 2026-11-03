`timescale 1ns/1ps
module tb_lesson_subtitle_font_bram;
reg clk=0;always #5 clk=~clk;
reg [7:0] code=0;reg [3:0] row=0;wire [15:0] reference_data,actual;
lesson_subtitle_font reference_font(code,row,reference_data);
lesson_subtitle_font_bram dut(clk,code,row,actual);
initial begin
for(integer c=0;c<256;c=c+1)for(integer r=0;r<16;r=r+1)begin
@(negedge clk);code=c;row=r;@(posedge clk);#2;
if(actual!==reference_data)$fatal(1,"BRAM FONT code=%0d row=%0d got=%h expected=%h",c,r,actual,reference_data);
end
$display("TEST_PASS caption primitive all 4096 rows");$finish;
end
endmodule
