`timescale 1ns/1ps
// Real application scheduler, BMP parser/scaler, SDRAM writer and display
// commit. Directory metadata, physical-sector bytes and FIFO storage are
// modeled; the real FAT reader and virtual-sector bridge remain connected.
module tb_practice_prefetch_pipeline;
reg clk=0, mem_clk=0, pixel_clk=0, rst=1;
always #5 clk=~clk;
always #4 mem_clk=~mem_clk;
always #20 pixel_clk=~pixel_clk;
reg prefetch_enable=0, image_request=0, image_request_settings=0, home_request=0;
reg [3:0] image_request_idx=0, prefetch_image_idx=0;
wire write_req,write_ack,write_en,finish,fifo_clear,app_write;
wire [31:0] write_data;
wire [20:0] app_address;
wire [1:0] write_index,source_index,display_index;
wire [3:0] source_image,display_image;
wire source_valid,commit_toggle,commit_ack;
wire settings_entry;
reg finish_toggle=0;
integer wp=0,rp=0,writes=0,frames=0,loads=0,cycles=0;
wire [8:0] occupancy=wp-rp;
reg [31:0] fifo[0:511];
reg [31:0] memory[0:921599];
reg [3:0] metadata_index=0;
reg metadata_valid=0,scan_complete=0;
reg [7:0] sd_data=0;
reg sd_valid=0,sd_end=0;
reg frame_boundary=0;
integer pixel_cycles=0;
sd_card_bmp #(.PREFETCH_ENABLE(1)) dut(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),
 .home_request(home_request),.image_request(image_request),.image_request_idx(image_request_idx),
 .image_request_zoom(3'd2),.image_request_prev(1'b0),.image_request_settings(image_request_settings),
 .prefetch_enable(prefetch_enable),.prefetch_image_idx(prefetch_image_idx),
 .zoom_request(1'b0),.zoom_level(3'd2),.zoom_image_idx(4'd0),
 .narration_enable(1'b0),.voice_speed_level(2'd1),.voice_speed_toggle(1'b0),
 .voice_fifo_space_available(1'b1),.voice_fifo_empty(1'b1),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_finish_toggle(finish_toggle),
 .write_buf_idx(write_index),.disp_buf_idx(source_index),.display_image_idx(source_image),
 .display_valid(source_valid),.display_commit_toggle(commit_toggle),
 .display_commit_ack_toggle(commit_ack),.write_req(write_req),.write_req_ack(write_ack),
 .write_en(write_en),.write_data(write_data),.SD_MISO(1'b1),
 .content_ready(),.state_code(),.display_page_right(),.display_settings_entry(settings_entry),
 .debug_event_toggle(),.auto_play_active(),.display_zoom_level(),
 .voice_fifo_write(),.voice_fifo_data(),.voice_start_toggle(),.voice_end_toggle(),
 .voice_stop_toggle(),.voice_clip_index(),.voice_sample_total(),.narration_busy(),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI());
// Match frame_read_write's production defaults, including its 512-word FIFO.
frame_fifo_write #(.BURST_BITS(9),.BURST_SIZE(256)) writer(
 .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.App_rd_busy(1'b0),.App_wr_en(app_write),.App_wr_addr(app_address),
 .write_req(write_req),.write_req_ack(write_ack),.write_finish(finish),
 .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd614400),
 .write_addr_3(21'd0),.write_addr_index(write_index),.write_len(21'd307200),
 .fifo_aclr(fifo_clear),.rdusedw(occupancy),.O_wr_busy());
frame_buffer_commit #(.TRANSITION_STEPS(8)) commit(
 .pixel_clk(pixel_clk),.pixel_rst(rst),.frame_boundary(frame_boundary),
 .source_buf_idx(source_index),.source_image_idx(source_image),.source_page_right(1'b0),
 .source_settings_entry(settings_entry),.source_zoom_level(3'd2),.source_display_valid(source_valid),
 .source_commit_toggle(commit_toggle),.commit_ack_toggle(commit_ack),
 .display_buf_idx(display_index),.display_image_idx(display_image),
 .transition_buf_idx(),.display_zoom_level(),.display_valid(),.lesson_image_ready(),
 .transition_active(),.transition_alpha(),.transition_effect());
always @(posedge pixel_clk)begin
 pixel_cycles<=pixel_cycles+1;frame_boundary<=pixel_cycles%200==0;
end
always @(posedge clk or posedge fifo_clear)begin
 if(fifo_clear)wp=0;
 else if(!rst && write_en)begin
  if(wp-rp>=512)$fatal(1,"FIFO overflow");
  fifo[wp%512]=write_data;wp=wp+1;
 end
end
always @(posedge mem_clk or posedge fifo_clear)begin
 if(fifo_clear)begin rp=0;writes=0;end
 else if(!rst && app_write)begin
  if(wp<=rp)$fatal(1,"FIFO underflow");
  if(app_address>=921600)$fatal(1,"writer address outside frame buffers");
  memory[app_address]=fifo[rp%512];rp=rp+1;writes=writes+1;
 end
end
always @(posedge mem_clk)begin
 if(rst)finish_toggle<=0;
 else if(finish)begin
  if(writes!=307200)$fatal(1,"incomplete writer %0d",writes);
  finish_toggle<=~finish_toggle;frames=frames+1;
  $display("FRAME_FINISH frame=%0d image=%0d source_ready=%b scaler_done=%b source_seen=%b",frames,dut.load_idx,dut.bmp_ready,dut.scaler_done_seen,dut.source_done_seen);
 end
end
always @(posedge clk)if(!rst)begin
 cycles=cycles+1;
 if(dut.load_start_pulse)begin loads=loads+1;$display("LOAD image=%0d prefetch=%b",dut.load_idx,dut.load_is_prefetch);end
 if(dut.bmp_load_error_pulse || dut.scaler_overrun)$fatal(1,"BMP/scaler failed bmp_error=%b overrun=%b image=%0d",dut.bmp_load_error_pulse,dut.scaler_overrun,dut.load_idx);
 if(dut.bmp_read_m0.short_sector_end)$display("SHORT_SECTOR bytes=%0d valid=%b virtual_end=%b address=%h",dut.bmp_read_m0.sector_byte_count,dut.bmp_sd_sec_read_data_valid,dut.virtual_sd_sec_read_end,dut.bmp_sd_sec_read_addr);
 if(cycles%2000000==0)$display("PROGRESS cycles=%0d busy=%b bmp_state=%0d writer=%0d writes=%0d source=%b scaler_done=%b bridge=%0d reader=%0d",cycles,dut.load_busy,dut.bmp_read_m0.state,writer.state,writes,dut.source_done_seen,dut.scaler_done_seen,dut.u_fat32_virtual_sector_bridge.state,dut.u_fat32_virtual_sector_bridge.u_file_reader.state);
end
function automatic [7:0] byte_at(input integer idx,input integer image);
 integer w,h,total,rel,row,col,component,value;
 begin
  w=image==3?1280:640;h=image==3?960:480;total=54+w*h*3;value=0;
  case(idx)
   0:value="B";1:value="M";
   2,3,4,5:value=total>>((idx-2)*8);
   10:value=54;14:value=40;
   18,19:value=w>>((idx-18)*8);22,23:value=h>>((idx-22)*8);
   26:value=1;28:value=24;
   default:if(idx>=54 && idx<total)begin
    rel=idx-54;row=rel/(w*3);col=(rel%(w*3))/3;component=rel%3;
    case(component)0:value=row;1:value=col;2:value=image;endcase
   end
  endcase
  byte_at=value[7:0];
 end
endfunction
initial forever begin : sd_model
 integer address,image,offset,cluster,next_cluster,size;
 wait(!rst && dut.bridge_sd_read);
 address=dut.bridge_sd_read_addr;
 cluster=((address-4096)/8)+2;
 image=(cluster-128)/1024;
 offset=(address-4096-(128+image*1024-2)*8)*512;
 for(integer b=0;b<512;b=b+1)begin
  @(negedge clk);sd_valid=1;
  if(address>=32 && address<192)begin
   cluster=(address-32)*128+b/4;
   image=(cluster-128)/1024;
   size=image==3?3686454:921654;
   next_cluster=(cluster-(128+image*1024)+1)*4096>=size?'h0fffffff:cluster+1;
   sd_data=next_cluster>>((b%4)*8);
  end else sd_data=byte_at(offset+b,image);
  // Three cycles per byte exceed the scaler's output interval for 1:1
  // input. Physical SPI is slower still; do not overdrive the line buffers.
  @(negedge clk);sd_valid=0;@(negedge clk);
 end
 @(negedge clk);sd_end=1;
 @(negedge clk);sd_end=0;
 wait(!dut.bridge_sd_read);repeat(4)@(negedge clk);
end
task automatic request_image(input [3:0] image);
 @(negedge clk);image_request_idx=image;image_request=1;
 @(negedge clk);image_request=0;
endtask
task automatic request_home;
 @(negedge clk);home_request=1;
 @(negedge clk);home_request=0;
 wait(display_image==12 && commit_ack==commit_toggle);
endtask
initial begin
 // Bypass only directory/physical-medium boundaries. The FAT reader, parser, scaler,
 // write request/ACK, pixel count, write_finish and display ACK stay real.
 force dut.sd_init_done=1'b1;
 force dut.fs_scan_busy=1'b0;
 force dut.fs_scan_done=scan_complete;
 force dut.fs_file_found_valid=metadata_valid;
 force dut.fs_file_found_index=metadata_index;
 force dut.fs_file_found_cluster=32'd128+metadata_index*32'd1024;
 force dut.fs_file_found_size=metadata_index==3?32'd3686454:32'd921654;
 force dut.fs_scan_error=8'd0;
 force dut.fs_sectors_per_cluster=8'd8;
 force dut.fs_sectors_per_cluster_shift=3'd3;
 force dut.fs_fat_start_lba=32'd32;
 force dut.fs_data_start_lba=32'd4096;
 force dut.fs_max_cluster=32'd20000;
 force dut.sd_sec_read_data=sd_data;
 force dut.sd_sec_read_data_valid=sd_valid;
 force dut.sd_sec_read_end=sd_end;
 repeat(5)@(negedge clk);rst=0;
 wait(dut.scan_start_pulse);repeat(3)@(negedge clk);
 for(integer i=0;i<13;i=i+1)begin
  metadata_index=i;metadata_valid=1;@(negedge clk);metadata_valid=0;@(negedge clk);
 end
 scan_complete=1;@(negedge clk);scan_complete=0;
 wait(display_image==12 && commit_ack==commit_toggle && source_valid);
 $display("HOME_COMMITTED");
 @(negedge clk);prefetch_enable=1;prefetch_image_idx=3;
 wait(dut.entry_cache_valid);
 wait(dut.load_is_prefetch && dut.load_idx==3);
 repeat(200)@(negedge clk);
 image_request_settings=1;
 request_image(0);
 wait(display_image==0 && commit_ack==commit_toggle);
 if(frames!=2 || loads!=3 || !dut.load_busy || !settings_entry ||
    !dut.entry_cache_valid || dut.entry_cache_buf_idx!=1 ||
    dut.prefetch_valid || dut.first_lesson_frame_ready)
    $fatal(1,"settings waited for quiz read or lost the shared entry cache");
 $display("SETTINGS_DURING_QUIZ_READ frames=%0d loads=%0d",frames,loads);
 @(negedge clk);image_request_settings=0;
 request_image(0);
 wait(!settings_entry && commit_ack==commit_toggle);
 if(frames!=2 || loads!=3 || !dut.load_busy || !dut.first_lesson_frame_ready)
   $fatal(1,"learning entry did not bypass active quiz read");
 $display("LESSON_DURING_QUIZ_READ frames=%0d loads=%0d",frames,loads);
 request_home(); // HOME is a real foreground reload, queued behind the quiz.
 request_image(0);
 wait(display_image==0 && commit_ack==commit_toggle);
 if(frames!=4 || loads!=4 || settings_entry || !dut.first_lesson_frame_ready ||
    display_index!=1 || !dut.prefetch_valid)
    $fatal(1,"first lesson did not reuse the shared cache");
 request_image(1);
 wait(display_image==1 && commit_ack==commit_toggle);
 if(!dut.prefetch_valid || frames!=5 || !dut.entry_cache_valid)
   $fatal(1,"prefetch or queued lesson missing");
 request_image(3);
 wait(display_image==3 && commit_ack==commit_toggle);
 if(frames!=5 || loads!=5 || display_index!=2)$fatal(1,"cache hit reread image");
 request_image(1);
 wait(display_image==1 && commit_ack==commit_toggle);
 if(frames!=6)$fatal(1,"cannot navigate away from cache");
 $display("TEST_PASS real HOME/settings/lesson cache, quiz prefetch, queued navigation and atomic display");$finish;
end
initial begin #550000000;$fatal(1,"pipeline timeout busy=%b bmp=%0d writer=%0d frames=%0d",dut.load_busy,dut.bmp_read_m0.state,writer.state,frames);end
endmodule
