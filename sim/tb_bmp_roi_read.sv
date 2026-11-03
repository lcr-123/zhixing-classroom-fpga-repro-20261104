`timescale 1ns/1ps
// Compare identical original BMP bytes through native and cropped-read paths.
module tb_bmp_roi_read #(parameter integer PRODUCTION=0);
localparam W=PRODUCTION?640:8, H=PRODUCTION?480:6;
reg clk=0,rst=1,start=0;
always #5 clk=~clk;
reg [15:0] width=8,height=6;
reg [2:0] zoom=2;
integer pixel_offset=54;
wire [1:0] ready,wreq,read_req,sstart,svalid,out_valid,done,busy,error_pulse,recover,overrun;
wire [31:0] address[0:1];
wire [15:0] sw[0:1],sh[0:1],first_row[0:1],row_count[0:1];
wire [23:0] source_rgb[0:1],rgb[0:1];
reg [1:0] ack=0,scaler_start=0,valid=0,sec_end=0;
reg [7:0] data[0:1];
integer requests[0:1],count[0:1],done_cycle[0:1];
integer cycles=0,errors=0,case_count=0;
reg finished[0:1];
reg [23:0] frame_data[0:1][0:W*H-1];
function automatic [7:0] byte_at(input integer index);
 integer stride,total,relative,row,col,component,value;
 begin
  stride=(width*3+3)&~3;total=pixel_offset+stride*height;
  value=0;
  case(index)
   0:value="B";1:value="M";
   2,3,4,5:value=total>>((index-2)*8);
   10,11,12,13:value=pixel_offset>>((index-10)*8);
   14:value=40;
   18,19:value=width>>((index-18)*8);
   22,23:value=height>>((index-22)*8);
   26:value=1;28:value=24;
   default: if(index>=pixel_offset && index<total)begin
    relative=index-pixel_offset;row=relative/stride;col=(relative%stride)/3;component=relative%3;
    component=(relative%stride)%3;
    if(relative%stride<width*3)case(component)
     0:value=(row^col)*37;1:value=col*19+row*83;2:value=col*73+row*17;
    endcase
   end
  endcase
  byte_at=value[7:0];
 end
endfunction
for(genvar n=0;n<2;n=n+1)begin: path
 bmp_read #(.CROP_READ_ENABLE(n),.SD_PROGRESS_TIMEOUT_CYCLES(100000)) reader(
  .clk(clk),.rst(rst),.ready(ready[n]),.scan_start(1'b0),.scan_start_sector(32'd0),
  .scan_max_sector(32'd0),.scan_target_count(4'd0),.scan_done(),.scan_found_valid(),
  .scan_found_sector(),.scan_found_total(),.scan_found_voice(),.scan_found_voice_offset(),
  .load_start(start),.load_sector(32'd0),.load_error_pulse(error_pulse[n]),.sd_recover_pulse(recover[n]),
  .sd_init_done(1'b1),.state_code(),.bmp_width(W[15:0]),.bmp_height(H[15:0]),
  .source_width(sw[n]),.source_height(sh[n]),.write_req(wreq[n]),.write_req_ack(ack[n]),
  .source_start(sstart[n]),.source_first_row(first_row[n]),.source_roi_rows(row_count[n]),
  .sd_sec_read(read_req[n]),.sd_sec_read_addr(address[n]),.sd_sec_read_data(data[n]),
  .sd_sec_read_data_valid(valid[n]),.sd_sec_read_end(sec_end[n]),.sd_sec_read_error(1'b0),
  .bmp_data_wr_en(svalid[n]),.bmp_data(source_rgb[n]));
 bmp_nearest_scaler #(.OUTPUT_WIDTH(W),.OUTPUT_HEIGHT(H),
  .MAX_SOURCE_WIDTH(PRODUCTION?1280:32),.SOURCE_ROI_ENABLE(n),.ZOOM_FOCUS_LEFT(1)) scaler(
  .clk(clk),.rst(rst),.start(scaler_start[n]),.source_width(sw[n]),.source_height(sh[n]),
  .zoom_level(zoom),.source_valid(svalid[n]),.source_rgb(source_rgb[n]),.source_start(sstart[n]),
  .output_valid(out_valid[n]),.output_rgb(rgb[n]),.busy(busy[n]),.done(done[n]),
  .source_overrun(overrun[n]),.source_first_row(first_row[n]),.source_row_count(row_count[n]));
 initial forever begin
  wait(wreq[n]);@(negedge clk);ack[n]=1;
  repeat(3)@(negedge clk);ack[n]=0;
  repeat(3)@(negedge clk);scaler_start[n]=1;
  @(negedge clk);scaler_start[n]=0;
 end
 initial forever begin
  integer offset;
  wait(read_req[n] && !rst);offset=address[n]*512;requests[n]=requests[n]+1;
  for(integer b=0;b<512;b=b+1)begin
   @(negedge clk);valid[n]=1;data[n]=byte_at(offset+b);
   @(negedge clk);valid[n]=0;
   repeat(PRODUCTION?6:63)@(negedge clk);
  end
  @(negedge clk);sec_end[n]=1;
  @(negedge clk);sec_end[n]=0;wait(!read_req[n]);
  repeat(4)@(negedge clk);
 end
 always @(posedge clk)if(!rst)begin
  if(error_pulse[n] || recover[n])errors=errors+1;
  if(out_valid[n])begin
   if(count[n]>=W*H)$fatal(1,"extra pixel path%0d",n);
   frame_data[n][count[n]]=rgb[n];count[n]=count[n]+1;
  end
  if(done[n])begin finished[n]=1;done_cycle[n]=cycles;end
 end
end
always @(posedge clk)cycles=cycles+1;
task automatic run_case(input integer source_w,source_h,level,offset);
 integer stride,ch,first,end_byte,begin_byte,native_requests,roi_requests,t0;
 begin
  @(negedge clk);width=source_w;height=source_h;zoom=level;pixel_offset=offset;errors=0;t0=cycles;
  for(integer n=0;n<2;n=n+1)begin requests[n]=0;count[n]=0;finished[n]=0;end
  start=1;@(negedge clk);start=0;
  wait(finished[0] && finished[1]);
  // The last pixel can precede the SD sector's padding/CRC and end handshake.
  wait(ready==2'b11);repeat(5)@(negedge clk);
  if(ready!=2'b11 || busy!=0 || overrun!=0 || errors || count[0]!=W*H || count[1]!=W*H)
   $fatal(1,"incomplete z%0d ready=%b busy=%b overrun=%b errors=%0d counts=%0d/%0d",level,ready,busy,overrun,errors,count[0],count[1]);
  for(integer p=0;p<W*H;p=p+1)
   if(frame_data[0][p]!==frame_data[1][p])$fatal(1,"ROI changed z%0d %0dx%0d pixel%0d got=%h expected=%h",level,source_w,source_h,p,frame_data[1][p],frame_data[0][p]);
  stride=(source_w*3+3)&~3;
  ch=level==3?source_h*4/5:level==4?source_h*2/3:source_h;if(ch==0)ch=1;
  first=(source_h-ch)/2;begin_byte=offset+first*stride;end_byte=begin_byte+ch*stride;
  native_requests=1+(offset+stride*source_h+511)/512;
  roi_requests=1+(end_byte+511)/512-begin_byte/512;
  if(requests[0]!=native_requests || requests[1]!=roi_requests)
   $fatal(1,"unexpected sector counts %0d/%0d expected %0d/%0d",requests[0],requests[1],native_requests,roi_requests);
  if(PRODUCTION && level>=3 && done_cycle[1]>=done_cycle[0])$fatal(1,"crop was not faster");
  $display("ROI_IO %0dx%0d z%0d offset=%0d original_sectors=%0d roi_sectors=%0d original_cycles=%0d roi_cycles=%0d pixels_identical=%0d",source_w,source_h,level,offset,requests[0],requests[1],done_cycle[0]-t0,done_cycle[1]-t0,W*H);
  case_count=case_count+1;
 end
endtask
initial begin
 data[0]=0;data[1]=0;
 repeat(3)@(negedge clk);rst=0;
 if(PRODUCTION)begin
  run_case(640,480,3,54);run_case(640,480,4,54);
  run_case(640,480,3,512); // first desired pixel is on a sector boundary
 end else begin
  for(integer z=0;z<5;z=z+1)run_case(8,6,z,54);
  for(integer z=0;z<5;z=z+1)run_case(7,5,z,512);
  run_case(4,3,4,54);run_case(16,12,4,54);
 end
 $display("TEST_PASS tb_bmp_roi_read production=%0d cases=%0d",PRODUCTION,case_count);$finish;
end
initial begin #2000000000;$fatal(1,"ROI timeout");end
endmodule
