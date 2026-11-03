`timescale 1ns/1ps
module tb_fat32_chain_range;
reg clk=0;
always #5 clk=~clk;
reg rst=1, start=0, stop=0;
reg [31:0] limit=198, next_entry=2;
wire busy, done, valid, request;
wire [7:0] error_code;
wire [31:0] address, data_offset;
reg [7:0] response_data=0;
reg response_valid=0, response_end=0;
integer active_byte=-1, reads=0, received=0, fat_finished=0;
reg was_request=0;
reg [31:0] active_address;

fat32_file_reader #(.SD_PROGRESS_TIMEOUT_CYCLES(2048)) dut (
    .clk(clk), .rst(rst), .sd_init_done(1'b1), .start(start), .stop(stop),
    .allow_next_sector(1'b1), .first_cluster(32'd127), .file_size(32'd514),
    .start_offset(32'd0), .read_length(32'd513),
    .sectors_per_cluster(8'd1), .sectors_per_cluster_shift(3'd0),
    .fat_start_lba(32'd10), .data_start_lba(32'd100), .max_cluster(limit),
    .busy(busy), .done(done), .sector_done(), .data_valid(valid),
    .data_byte(), .data_offset(data_offset), .error_code(error_code),
    .sd_sec_read(request), .sd_sec_read_addr(address),
    .sd_sec_read_data(response_data), .sd_sec_read_data_valid(response_valid),
    .sd_sec_read_end(response_end), .sd_recover_pulse()
);

// Entry 127 occupies the last four sector bytes. The final byte and
// sector-end arrive together, so range checking cannot use a stale byte.
always @(negedge clk) begin
    if (rst) begin
        active_byte=-1; was_request=0;
        response_valid=0; response_end=0; fat_finished=0;
    end else begin
        if (valid) begin
            if (data_offset !== received) $fatal(1,"wrong stream offset");
            received=received+1;
        end
        response_valid=0; response_end=0;
        if (request && !was_request) begin
            if (active_byte>=0) $fatal(1,"overlapping SD request");
            reads=reads+1;
            case (reads)
                1: if (address!==32'd225) $fatal(1,"wrong first LBA");
                2: if (address!==32'd10) $fatal(1,"wrong FAT LBA");
                3: if (address!==32'd100+{4'd0,next_entry[27:0]}-32'd2)
                       $fatal(1,"wrong next-cluster LBA");
                default: $fatal(1,"unexpected additional read");
            endcase
            active_address=address; active_byte=0;
        end
        was_request=request;
        if (active_byte>=0) begin
            response_valid=1; response_data=8'ha6;
            if (active_address==10) begin
                response_data=0;
                case (active_byte)
                    508: response_data=next_entry[7:0];
                    509: response_data=next_entry[15:8];
                    510: response_data=next_entry[23:16];
                    511: response_data=next_entry[31:24];
                endcase
            end
            response_end=(active_byte==511);
            if (response_end) begin
                if (active_address==10) fat_finished=1;
                active_byte=-1;
            end else active_byte=active_byte+1;
        end
    end
end

task begin_case(input [31:0] bound, input [31:0] entry);
begin
    @(posedge clk); #1 rst=1; start=0; stop=0;
    repeat(3) @(posedge clk);
    #1 limit=bound; next_entry=entry; reads=0; received=0; rst=0; start=1;
    @(posedge clk); #1 start=0;
end
endtask

task run_case(input [31:0] bound, input [31:0] entry, input [7:0] expected_error);
integer cycles;
begin
    begin_case(bound,entry);
    cycles=0;
    while (!done && cycles<4000) begin @(posedge clk); #1 cycles=cycles+1; end
    if (!done || error_code!==expected_error)
        $fatal(1,"range result entry=%h max=%h got=%h expected=%h",
               entry,bound,error_code,expected_error);
    if ((expected_error==0 && (reads!=3 || received!=513)) ||
        (expected_error!=0 && (reads!=2 || received!=512)))
        $fatal(1,"invalid chain leaked a read/data entry=%h reads=%0d bytes=%0d",
               entry,reads,received);
    repeat(4) @(posedge clk);
end
endtask

initial begin
    run_case(198,2,0); run_case(198,0,8'h24); run_case(198,198,0);
    run_case(198,199,8'h24); run_case(198,1,8'h24);
    run_case(198,32'h0001_0002,8'h24); run_case(198,32'h0100_0002,8'h24);
    run_case(198,32'hf000_0002,0);
    run_case(198,32'h0fff_fff8,8'h25); run_case(198,127,8'h23);
    run_case(32'h0002_0010,32'h0001_ffff,0);
    run_case(32'h0002_0010,32'h0002_0010,0);
    run_case(32'h0002_0010,32'h0002_0011,8'h24);
    run_case(32'h0002_0010,32'h0003_0000,8'h24);
    begin_case(198,199);
    wait(fat_finished); @(posedge clk); #1 stop=1;
    repeat(5) @(posedge clk);
    #1 if (busy || request || valid || reads!=2)
        $fatal(1,"stop during FAT validation did not cancel");
    begin_case(198,198);
    wait(fat_finished); @(posedge clk); #1 rst=1;
    #1 if (busy || request || valid) $fatal(1,"reset during FAT validation failed");
    run_case(198,2,0);
    $display("TEST_PASS FAT chain range bounds, last byte/end, EOF, loop, stop/reset");
    $finish;
end
initial begin #1000000; $fatal(1,"timeout"); end
endmodule
