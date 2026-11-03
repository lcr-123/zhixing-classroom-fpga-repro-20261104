`timescale 1ns/1ps
module tb_bmp_roi_failures;
reg clk=0,rst=1,start=0,ack=0,source_start=0;
always #5 clk=~clk;
reg [15:0] first_row=0,rows=6;
reg [31:0] load_sector=0;
wire ready,write_req,read_req,valid,error_pulse,recover;
wire [31:0] addr;
reg [7:0] data=0;
reg data_valid=0,sector_end=0;
reg medium_busy=0;
integer requests=0,pixels=0,errors=0,recovers=0,fault=0;
bmp_read #(.CROP_READ_ENABLE(1),.SD_PROGRESS_TIMEOUT_CYCLES(128)) dut(
 .clk(clk),.rst(rst),.ready(ready),.scan_start(1'b0),.scan_start_sector(32'd0),
 .scan_max_sector(32'd0),.scan_target_count(4'd0),.scan_done(),.scan_found_valid(),
 .scan_found_sector(),.scan_found_total(),.scan_found_voice(),.scan_found_voice_offset(),
 .load_start(start),.load_sector(load_sector),.load_error_pulse(error_pulse),.sd_recover_pulse(recover),
 .sd_init_done(1'b1),.state_code(),.bmp_width(16'd8),.bmp_height(16'd6),
 .source_width(),.source_height(),.write_req(write_req),.write_req_ack(ack),
 .source_start(source_start),.source_first_row(first_row),.source_roi_rows(rows),
 .sd_sec_read(read_req),.sd_sec_read_addr(addr),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(data_valid),.sd_sec_read_end(sector_end),.sd_sec_read_error(1'b0),
 .bmp_data_wr_en(valid),.bmp_data());
function automatic [7:0] byte_at(input integer p);
 begin
  byte_at=0;
  case(p)
   0:byte_at="B";1:byte_at="M";2:byte_at=198;10:byte_at=54;
   14:byte_at=40;18:byte_at=8;22:byte_at=6;26:byte_at=1;28:byte_at=24;
   default:byte_at=p>=54?p:0;
  endcase
 end
endfunction
always @(posedge clk)if(!rst)begin
 if(valid)pixels=pixels+1;
 if(error_pulse)errors=errors+1;
 if(recover)recovers=recovers+1;
end
initial forever begin
 integer limit;
 wait(read_req && !rst);medium_busy=1;requests=requests+1;
 if(addr!=0)$fatal(1,"busy request replaced active address");
 limit=(requests==2 && fault==1)?511:512;
 if(requests==2 && fault==2)begin
  repeat(150)@(negedge clk);
 end else begin
  for(integer b=0;b<limit;b=b+1)begin
   @(negedge clk);data=byte_at(b);data_valid=1;
   @(negedge clk);data_valid=0;
  end
  @(negedge clk);sector_end=1;
  @(negedge clk);sector_end=0;
 end
 wait(!read_req);repeat(5)@(negedge clk);
 medium_busy=0;
end
task automatic run_case(input integer first,count,kind);
 begin
  wait(ready && !medium_busy);@(negedge clk);
  $display("ROI_FAILURE_CASE first=%0d count=%0d kind=%0d",first,count,kind);
  requests=0;pixels=0;errors=0;recovers=0;fault=kind;load_sector=0;
  first_row=first;rows=count;start=1;
  @(negedge clk);start=0;
  wait(write_req);@(negedge clk);ack=1;
  repeat(3)@(negedge clk);ack=0;
  repeat(3)@(negedge clk);source_start=1;
  @(negedge clk);source_start=0;
  // Busy requests cannot replace the in-flight multiplier or seek address.
  repeat(3)@(negedge clk);load_sector=77;start=1;
  @(negedge clk);start=0;
  if(kind==3)begin
   rst=1;repeat(3)@(negedge clk);rst=0;
  end
  wait(ready);repeat(8)@(negedge clk);
  if(kind==0 && (count==0 || first>=6 || first+count>6))begin
   if(errors!=1 || recovers!=0 || requests!=1 || pixels!=0)$fatal(1,"invalid ROI was not bounded");
  end else if(kind==1 || kind==2)begin
   if(errors!=1 || recovers!=1 || requests!=2)$fatal(1,"read failure was not reported %0d/%0d",errors,recovers);
  end else if(kind==3)begin
   if(pixels || errors || read_req)$fatal(1,"reset leaked partial ROI state");
  end else if(errors || recovers || requests!=2 || pixels!=8*count)
   $fatal(1,"ROI restore failed pixels=%0d expected=%0d errors=%0d",pixels,8*count,errors);
 end
endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 run_case(6,1,0);run_case(0,0,0);run_case(5,2,0);
 run_case(1,4,1);run_case(1,4,2);run_case(1,4,3);
 run_case(1,4,0);run_case(0,6,0);
 $display("TEST_PASS tb_bmp_roi_failures: invalid bounds, short sector, timeout, busy, reset/restore");$finish;
end
initial begin #5000000;$fatal(1,"ROI failure test timeout state=%0d reqs=%0d errors=%0d ready=%b write=%b",dut.state,requests,errors,ready,write_req);end
endmodule
