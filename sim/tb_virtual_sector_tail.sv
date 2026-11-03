`timescale 1ns/1ps
// Match sd_card_bmp's registered data/valid and direct sector-end interface.
// In particular, the consumer must have counted all 512 bytes before end.
module tb_virtual_sector_tail;
reg clk=0,rst=1,metadata_valid=0,request=0;
reg [31:0] size=54;
reg [7:0] data=0;
reg valid=0,ended=0;
wire read_req,tail_end,tail_valid,tail_error,recover;
wire [31:0] address;
wire [7:0] tail_data;
reg piped_valid=0;
reg [7:0] piped_data=0;
integer count=0,physical_reads=0,completed=0;
always #5 clk=~clk;
fat32_virtual_sector_bridge dut(
 .clk(clk),.rst(rst),.sd_init_done(1'b1),.metadata_clear(1'b0),
 .metadata_valid(metadata_valid),.metadata_index(4'd3),.metadata_cluster(32'd2),
 .metadata_size(size),.metadata_mask(),.sectors_per_cluster(8'd8),
 .sectors_per_cluster_shift(3'd3),.fat_start_lba(32'd32),
 .data_start_lba(32'd4096),.max_cluster(32'd20000),
 .virtual_read(request),.virtual_read_addr(32'h80300000),
 .virtual_read_data(tail_data),.virtual_read_data_valid(tail_valid),
 .virtual_read_end(tail_end),.virtual_read_error(tail_error),
 .physical_read(read_req),.physical_read_addr(address),
 .physical_read_data(data),.physical_read_data_valid(valid),
 .physical_read_end(ended),.sd_recover_pulse(recover));
always @(posedge clk)begin
 piped_valid<=tail_valid;piped_data<=tail_data;
 if(!rst)begin
  if(tail_error || recover)$fatal(1,"unexpected reader error");
  if(tail_end)begin
   if(count!=512)$fatal(1,"short sector at consumer bytes=%0d last_byte_pending=%b file_size=%0d",count,piped_valid,size);
   completed=completed+1;
   count=0;
  end else if(piped_valid)begin
   if(piped_data!==(count<size?count[7:0]:8'd0))$fatal(1,"tail data mismatch %0d",count);
   count=count+1;
  end
 end
end
initial forever begin
 wait(!rst && read_req);physical_reads=physical_reads+1;
 if(address!=4096 && address!=32)$fatal(1,"wrong LBA %0d",address);
 repeat(5)@(negedge clk);
 @(negedge clk);
 for(integer i=0;i<512;i=i+1)begin
  data=address==32?8'hff:i;valid=1;@(negedge clk);valid=0;repeat(2)@(negedge clk);
 end
 ended=1;@(negedge clk);ended=0;wait(!read_req);
end
task automatic read_tail(input integer file_size);
 integer expected;
 expected=completed+1;
 @(negedge clk);size=file_size;metadata_valid=1;
 @(negedge clk);metadata_valid=0;
 repeat(4)@(negedge clk);request=1;
 wait(tail_end);@(negedge clk);request=0;
 wait(completed==expected);repeat(8)@(negedge clk);
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 read_tail(1);read_tail(54);read_tail(511);read_tail(512);
 if(physical_reads!=8)$fatal(1,"duplicate physical request %0d",physical_reads);
 $display("TEST_PASS virtual EOF tails 1/54/511/512 with registered consumer and no duplicate read");$finish;
end
initial begin #200000;$fatal(1,"tail watchdog");end
endmodule
