`timescale 1ns/1ps
module tb_fat32_reader_sector_step;
reg clk=0;
always #5 clk=~clk;
reg rst=1, start=0, allow_next=1;
reg [7:0] spc=1;
reg [2:0] shift=0;
reg [31:0] offset=0;
reg [31:0] first_cluster=5, max_cluster=100;
wire busy, done, sector_done, valid, request;
wire [7:0] data, error_code;
wire [31:0] data_offset, address;
reg [7:0] response_data=0;
reg response_valid=0, response_end=0;
integer received=0, sectors=0, request_count=0, stall=0;
integer active_byte=-1;
reg was_request=0;
reg [31:0] active_address;
integer logical_sector, cluster_number, expected_address, entry;

fat32_file_reader #(.SD_PROGRESS_TIMEOUT_CYCLES(2048)) dut (
    .clk(clk), .rst(rst), .sd_init_done(1'b1), .start(start),
    .stop(1'b0), .allow_next_sector(allow_next), .first_cluster(first_cluster),
    .file_size(offset+32'd1029), .start_offset(offset), .read_length(32'd1028),
    .sectors_per_cluster(spc), .sectors_per_cluster_shift(shift),
    .fat_start_lba(32'd10), .data_start_lba(32'd100), .max_cluster(max_cluster),
    .busy(busy), .done(done), .sector_done(sector_done), .data_valid(valid),
    .data_byte(data), .data_offset(data_offset), .error_code(error_code),
    .sd_sec_read(request), .sd_sec_read_addr(address),
    .sd_sec_read_data(response_data), .sd_sec_read_data_valid(response_valid),
    .sd_sec_read_end(response_end), .sd_recover_pulse()
);

// Independent media model: logical clusters 5 -> 9 -> 13 -> 17.
// Check actual LBA requests, including pauses at a completed sector.
always @(negedge clk) begin
    if (rst) begin
        active_byte=-1; was_request=0;
        response_valid=0; response_end=0; stall=0; allow_next=1;
    end else begin
        if (valid) begin
            if (data_offset !== offset+received || data !== 8'ha6)
                $fatal(1,"stream mismatch spc=%0d offset=%0d got=%0d",spc,offset,data_offset);
            received=received+1;
        end
        if (sector_done) begin
            allow_next=0;
            stall=7;
        end else if (stall>0) begin
            stall=stall-1;
            if (stall==0) allow_next=1;
        end
        response_valid=0; response_end=0;
        if (request && !was_request) begin
            if (!allow_next) $fatal(1,"request during consumer pause");
            if (active_byte>=0) $fatal(1,"overlapping request");
            request_count=request_count+1;
            active_address=address;
            active_byte=0;
            if (address!=10) begin
                logical_sector=(offset/512)+sectors;
                cluster_number=5+4*(logical_sector/spc);
                expected_address=100+(cluster_number-2)*spc+(logical_sector%spc);
                if (address!==expected_address)
                    $fatal(1,"LBA mismatch spc=%0d n=%0d got=%0d expected=%0d",spc,sectors,address,expected_address);
                sectors=sectors+1;
            end
        end
        was_request=request;
        if (active_byte>=0) begin
            response_valid=1;
            response_data=8'ha6;
            if (active_address==10) begin
                entry=active_byte/4;
                response_data=0;
                if (active_byte%4==0 && entry>=5 && (entry-5)%4==0)
                    response_data=entry+4;
            end
            response_end=(active_byte==511);
            if (response_end) active_byte=-1;
            else active_byte=active_byte+1;
        end
    end
end

task run_case(input integer cluster_sectors, input integer cluster_shift,
              input integer start_byte);
integer cycles;
begin
    @(posedge clk); #1 rst=1;
    repeat(3) @(posedge clk);
    #1 spc=cluster_sectors; shift=cluster_shift; offset=start_byte;
    received=0; sectors=0; request_count=0; rst=0; start=1;
    @(posedge clk); #1 start=0;
    cycles=0;
    while (!done && cycles<15000) begin @(posedge clk); #1 cycles=cycles+1; end
    if (!done || error_code!=0 || received!=1028)
        $fatal(1,"read failed spc=%0d err=%h count=%0d",spc,error_code,received);
    if (sectors!=((start_byte%512+1028+511)/512))
        $fatal(1,"wrong number of data sectors");
    repeat(10) @(posedge clk);
end
endtask
task run_invalid_cluster(input [31:0] bad_cluster);
integer cycles;
begin
    @(posedge clk); #1 rst=1;
    repeat(3) @(posedge clk);
    #1 first_cluster=bad_cluster; max_cluster=100;
    offset=0; received=0; sectors=0; request_count=0; rst=0; start=1;
    @(posedge clk); #1 start=0;
    cycles=0;
    while (!done && cycles<100) begin @(posedge clk); #1 cycles=cycles+1; end
    if (!done || error_code!=8'h27 || request_count!=0)
        $fatal(1,"invalid start cluster accepted cluster=%h error=%h reads=%0d",
               bad_cluster,error_code,request_count);
end
endtask
task run_busy_start_reset;
begin
    @(posedge clk); #1 rst=1;
    repeat(3) @(posedge clk);
    #1 first_cluster=5; max_cluster=100;
    offset=0; received=0; sectors=0; request_count=0; rst=0; start=1;
    @(posedge clk); #1 start=0;
    wait(request);
    first_cluster=101; start=1;
    @(posedge clk); #1 start=0;
    repeat(8) @(posedge clk);
    #1 if (!busy || error_code!=0 || request_count!=1)
        $fatal(1,"busy start replaced active read");
    rst=1;
    #1 if (request || busy || valid)
        $fatal(1,"reset did not interrupt active read");
    repeat(3) @(posedge clk);
    #1 first_cluster=5;
    run_case(1,0,0);
end
endtask
initial begin
    run_case(1,0,0); run_case(1,0,509);
    run_case(2,1,0); run_case(2,1,1021);
    run_case(128,7,0); run_case(128,7,65533);
    run_invalid_cluster(32'd0); run_invalid_cluster(32'd1);
    run_invalid_cluster(32'd101); run_invalid_cluster(32'h0001_0000);
    run_busy_start_reset();
    $display("TEST_PASS reader sector step: fragmentation, pauses, invalid/busy/reset");
    $finish;
end
initial begin #2000000; $fatal(1,"timeout"); end
endmodule
