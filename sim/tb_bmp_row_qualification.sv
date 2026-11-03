`timescale 1ns/1ps
module tb_bmp_row_qualification;
    reg clk = 0;
    reg rst = 1;
    reg load_start = 0;
    reg write_req_ack = 0;
    reg source_start = 0;
    reg [7:0] data = 0;
    reg valid = 0;
    reg sector_end = 0;
    wire ready, read_req, write_req, pixel_valid, load_error, recover;
    wire [23:0] pixel_data;
    wire [31:0] read_address;
    wire [3:0] status;
    integer image_width = 4;
    integer image_height = 3;
    integer pixel_offset = 54;
    integer stride;
    integer file_length;
    integer pixel_end;
    integer pixel_count = 0;
    integer case_index;
    integer sector;
    integer byte_index;
    integer absolute_byte = 0;
    integer tests = 0;
    reg streaming = 0;
    reg abort_first_sector = 0;
    reg bubbles = 0;
    reg [23:0] expected_pixel;
    reg expected_qualification;
    always #5 clk = ~clk;

    bmp_read #(.SD_PROGRESS_TIMEOUT_CYCLES(128)) dut (
        .clk(clk), .rst(rst), .ready(ready),
        .scan_start(1'b0), .scan_start_sector(32'd0), .scan_max_sector(32'd0),
        .scan_target_count(4'd0), .scan_done(), .scan_found_valid(),
        .scan_found_sector(), .scan_found_total(), .scan_found_voice(),
        .scan_found_voice_offset(), .load_start(load_start), .load_sector(32'd0),
        .load_error_pulse(load_error), .sd_recover_pulse(recover),
        .sd_init_done(1'b1), .state_code(status),
        .bmp_width(16'd172), .bmp_height(16'd6),
        .source_width(), .source_height(), .write_req(write_req),
        .write_req_ack(write_req_ack), .source_start(source_start),
        .sd_sec_read(read_req), .sd_sec_read_addr(read_address),
        .sd_sec_read_data(data), .sd_sec_read_data_valid(valid),
        .sd_sec_read_end(sector_end), .sd_sec_read_error(1'b0),
        .bmp_data_wr_en(pixel_valid), .bmp_data(pixel_data)
    );

    function automatic [23:0] reference_pixel(input integer index);
        reg [7:0] b, g, r;
        begin
            b = index;
            g = 8'h40 + index;
            r = 8'h80 + index;
            reference_pixel = {r, g, b};
        end
    endfunction

    function automatic [7:0] image_byte(input integer offset);
        integer relative, row_position, index;
        reg [23:0] rgb;
        begin
            image_byte = 8'hdc; // distinctive padding and trailer bytes
            if (offset < 54) begin
                image_byte = 0;
                case (offset)
                    0: image_byte = "B";
                    1: image_byte = "M";
                    2,3,4,5: image_byte = file_length >> (8*(offset-2));
                    10,11,12,13: image_byte = pixel_offset >> (8*(offset-10));
                    14: image_byte = 40;
                    18,19,20,21: image_byte = image_width >> (8*(offset-18));
                    22,23,24,25: image_byte = image_height >> (8*(offset-22));
                    26: image_byte = 1;
                    28: image_byte = 24;
                    default: ;
                endcase
            end else if (offset >= pixel_offset && offset < pixel_end) begin
                relative = offset - pixel_offset;
                row_position = relative % stride;
                index = (relative / stride)*image_width + row_position/3;
                rgb = reference_pixel(index);
                if (row_position < image_width*3)
                    image_byte = rgb >> (8*(row_position%3));
            end
        end
    endfunction

    // Geometric file reference checks qualification BEFORE the sample edge;
    // registered RGB results are checked independently AFTER that edge.
    always @(posedge clk) begin
        if (!rst && streaming && valid) begin
            expected_qualification = absolute_byte >= pixel_offset &&
                absolute_byte < pixel_end &&
                ((absolute_byte-pixel_offset) % stride) < image_width*3;
            if (dut.bmp_data_valid !== expected_qualification)
                $fatal(1, "byte qualification mismatch file=%0d width=%0d", absolute_byte, image_width);
        end
        #1;
        if (!rst) begin
            if (load_error || recover)
                $fatal(1, "valid test image rejected at status=%h", status);
            if (pixel_valid) begin
                expected_pixel = reference_pixel(pixel_count);
                if (!streaming || pixel_count >= image_width*image_height || pixel_data !== expected_pixel)
                    $fatal(1, "RGB mismatch pixel=%0d got=%h expected=%h", pixel_count, pixel_data, expected_pixel);
                pixel_count = pixel_count + 1;
            end
        end
    end

    task automatic send_sector(input integer index);
        begin
            for (byte_index = 0; byte_index < (streaming && abort_first_sector ? 101 : 512); byte_index = byte_index+1) begin
                @(negedge clk);
                absolute_byte = index*512 + byte_index;
                data = image_byte(absolute_byte);
                valid = 1;
                if (bubbles && byte_index % 7 == 3) begin
                    @(negedge clk);
                    valid = 0;
                    repeat (2) @(negedge clk);
                end
            end
            @(negedge clk); valid = 0;
            if (!streaming || !abort_first_sector) begin
                sector_end = 1;
                @(negedge clk); sector_end = 0;
            end
        end
    endtask

    initial begin
        // 169..172 exercise all padding counts and rows crossing sectors.
        // The target width is 172, so these are valid within the 0.5..2 range.
        for (case_index = 0; case_index < 14; case_index = case_index+1) begin
            image_width = 169 + case_index%4;
            image_height = 3 + case_index%2;
            pixel_offset = case_index < 4 ? 54 : case_index < 8 ? 510 : 514;
            bubbles = case_index%2;
            abort_first_sector = case_index == 12;
            if (abort_first_sector) pixel_offset = 54;
            stride = (image_width*3 + 3) & ~3;
            pixel_end = pixel_offset + stride*image_height;
            file_length = pixel_end + 37; // legal trailing bytes must be ignored
            @(negedge clk); rst = 1;
            streaming = 0;
            pixel_count = 0;
            repeat (4) @(negedge clk);
            rst = 0;
            @(negedge clk); load_start = 1;
            @(negedge clk); load_start = 0;
            wait (read_req);
            send_sector(0);
            wait (write_req);
            @(negedge clk); write_req_ack = 1;
            wait (!write_req);
            @(negedge clk); write_req_ack = 0;
            repeat (5) @(negedge clk);
            source_start = 1;
            @(negedge clk); source_start = 0;
            wait (read_req);
            streaming = 1;
            for (sector = 0; sector < (pixel_end+511)/512; sector = sector+1) begin
                if (!read_req || read_address != sector)
                    $fatal(1, "incorrect sector request: expected=%0d actual=%0d", sector, read_address);
                send_sector(sector);
                if (abort_first_sector) begin
                    // Interrupt after two B/G/R components have been accepted.
                    // A later image must begin at B again, with no stale pixel.
                    @(negedge clk); rst = 1;
                    repeat (3) @(negedge clk);
                    if (pixel_valid || dut.bmp_data_valid)
                        $fatal(1, "reset retained pixel qualification");
                    break;
                end
                if (sector+1 < (pixel_end+511)/512) wait (read_req);
            end
            wait (ready);
            repeat (3) @(negedge clk);
            if (!abort_first_sector && pixel_count != image_width*image_height)
                $fatal(1, "pixel count mismatch: got=%0d expected=%0d", pixel_count, image_width*image_height);
            streaming = 0;
            tests = tests+1;
        end
        $display("TEST_PASS tb_bmp_row_qualification cases=%0d", tests);
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "bounded BMP row test timeout");
    end
endmodule
