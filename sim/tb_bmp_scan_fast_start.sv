`timescale 1ns/1ps

module tb_bmp_scan_fast_start;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg scan_start = 1'b0;
    reg sd_init_done = 1'b0;
    reg [7:0] sd_sec_read_data = 8'd0;
    reg sd_sec_read_data_valid = 1'b0;
    reg sd_sec_read_end = 1'b0;

    wire scan_done;
    wire scan_found_valid;
    wire [31:0] scan_found_sector;
    wire [3:0] scan_found_total;
    wire sd_sec_read;
    wire [31:0] sd_sec_read_addr;

    integer request_count = 0;
    integer found_pulses = 0;
    integer file_len = 921654;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (scan_found_valid)
            found_pulses <= found_pulses + 1;
    end

    function automatic [7:0] bmp_byte(input integer byte_index);
        begin
            case (byte_index)
                0: bmp_byte = "B";
                1: bmp_byte = "M";
                2: bmp_byte = file_len[7:0];
                3: bmp_byte = file_len[15:8];
                4: bmp_byte = file_len[23:16];
                5: bmp_byte = file_len[31:24];
                10: bmp_byte = 8'd54;
                14: bmp_byte = 8'd40;
                18: bmp_byte = 8'h80;
                19: bmp_byte = 8'h02;
                22: bmp_byte = 8'hE0;
                23: bmp_byte = 8'h01;
                26: bmp_byte = 8'd1;
                28: bmp_byte = 8'd24;
                default: bmp_byte = 8'd0;
            endcase
        end
    endfunction

    task automatic send_requested_sector(
        input [31:0] expected_address,
        input integer is_bmp
    );
        integer byte_index;
        begin
            wait (sd_sec_read);
            if (sd_sec_read_addr !== expected_address)
                $fatal(1, "sector request mismatch: expected=%0d actual=%0d",
                       expected_address, sd_sec_read_addr);
            request_count = request_count + 1;
            for (byte_index = 0; byte_index < 512; byte_index = byte_index + 1) begin
                @(negedge clk);
                sd_sec_read_data = is_bmp ? bmp_byte(byte_index) : 8'd0;
                sd_sec_read_data_valid = 1'b1;
                @(negedge clk);
                sd_sec_read_data_valid = 1'b0;
            end
            @(negedge clk);
            sd_sec_read_end = 1'b1;
            @(negedge clk);
            sd_sec_read_end = 1'b0;
        end
    endtask

    bmp_read dut (
        .clk(clk),
        .rst(rst),
        .ready(),
        .scan_start(scan_start),
        .scan_start_sector(32'd0),
        .scan_max_sector(32'd10000),
        .scan_target_count(4'd1),
        .scan_done(scan_done),
        .scan_found_valid(scan_found_valid),
        .scan_found_sector(scan_found_sector),
        .scan_found_total(scan_found_total),
        .scan_found_voice(),
        .scan_found_voice_offset(),
        .load_start(1'b0),
        .load_sector(32'd0),
        .load_error_pulse(),
        .sd_recover_pulse(),
        .sd_init_done(sd_init_done),
        .state_code(),
        .bmp_width(16'd640),
        .bmp_height(16'd480),
        .source_width(),
        .source_height(),
        .write_req(),
        .write_req_ack(1'b0),
        .source_start(1'b0),
        .sd_sec_read(sd_sec_read),
        .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),
        .sd_sec_read_error(1'b0),
        .bmp_data_wr_en(),
        .bmp_data()
    );

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        sd_init_done = 1'b1;
        @(negedge clk);
        scan_start = 1'b1;
        @(negedge clk);
        scan_start = 1'b0;

        // 新卡首图尚未核验，安全构建必须从 LBA0 开始而非复用旧卡。
        send_requested_sector(32'd0, 1);
        wait (scan_done);
        repeat (2) @(posedge clk);

        if (scan_found_total != 4'd1 || found_pulses != 1 ||
            scan_found_sector != 32'd0 || request_count != 1)
            $fatal(1, "fast scan failed: total=%0d pulses=%0d sector=%0d reads=%0d",
                   scan_found_total, found_pulses, scan_found_sector, request_count);

        $display("TEST_PASS tb_bmp_scan_fast_start safe_start_lba=0 reads=1");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "test timeout");
    end
endmodule
