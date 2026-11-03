`timescale 1ns/1ps

module tb_bmp_read_scaling;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg scan_start = 1'b0;
    reg load_start = 1'b0;
    reg sd_init_done = 1'b0;
    reg write_req_ack = 1'b0;
    reg source_start = 1'b0;
    reg [7:0] sd_sec_read_data = 8'd0;
    reg sd_sec_read_data_valid = 1'b0;
    reg sd_sec_read_end = 1'b0;
    wire ready;
    wire scan_done;
    wire scan_found_valid;
    wire [3:0] scan_found_total;
    wire scan_found_voice;
    wire [31:0] scan_found_voice_offset;
    wire write_req;
    wire sd_sec_read;
    wire [15:0] source_width;
    wire [15:0] source_height;
    wire bmp_data_wr_en;
    wire [23:0] bmp_data;
    wire load_error_pulse;
    wire sd_recover_pulse;
    wire [3:0] state_code;

    reg [23:0] captured [0:31];
    integer captured_count = 0;
    integer scan_index;
    integer pixel;
    integer load_error_count = 0;
    integer recover_count = 0;
    integer scan_found_pulses = 0;
    integer scan_voice_pulses = 0;
    reg [7:0] header_pixel_offset = 8'd54;
    reg [7:0] header_dib_size = 8'd40;
    reg [7:0] header_planes = 8'd1;
    reg [7:0] header_file_len = 8'd102;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (load_error_pulse)
            load_error_count <= load_error_count + 1;
        if (sd_recover_pulse)
            recover_count <= recover_count + 1;
        if (scan_found_valid)
            scan_found_pulses <= scan_found_pulses + 1;
        if (scan_found_valid && scan_found_voice)
            scan_voice_pulses <= scan_voice_pulses + 1;
    end

    always @(posedge clk) begin
        if (bmp_data_wr_en) begin
            captured[captured_count] <= bmp_data;
            captured_count <= captured_count + 1;
        end
    end

    function automatic [7:0] bmp_byte(input integer index);
        integer relative;
        integer row_byte;
        integer pixel_index;
        integer component;
        begin
            bmp_byte = 8'd0;
            case (index)
                0: bmp_byte = "B";
                1: bmp_byte = "M";
                2: bmp_byte = header_file_len;
                10: bmp_byte = header_pixel_offset;
                14: bmp_byte = header_dib_size;
                18: bmp_byte = 8'd5;
                22: bmp_byte = 8'd3;
                26: bmp_byte = header_planes;
                28: bmp_byte = 8'd24;
                default: begin
                    if ((index >= 54) && (index < 102)) begin
                        relative = index - 54;
                        row_byte = relative % 16;
                        if (row_byte < 15) begin
                            pixel_index = (relative / 16) * 5 + (row_byte / 3);
                            component = row_byte % 3;
                            case (component)
                                0: bmp_byte = pixel_index[7:0];
                                1: bmp_byte = 8'h40 + pixel_index[7:0];
                                default: bmp_byte = 8'h80 + pixel_index[7:0];
                            endcase
                        end else begin
                            bmp_byte = 8'hFF;
                        end
                    end
                end
            endcase
        end
    endfunction

    task automatic send_sector;
        integer byte_index;
        integer pixel_byte_index;
        begin
            for (byte_index = 0; byte_index < 512; byte_index = byte_index + 1) begin
                @(negedge clk);
                sd_sec_read_data = bmp_byte(byte_index);
                sd_sec_read_data_valid = 1'b1;
                @(negedge clk);
                if (state_code == 4'd4 && byte_index >= 54 && byte_index < 102) begin
                    pixel_byte_index = byte_index - 54 + 1;
                    if (dut.row_byte_pos !== (pixel_byte_index % 16))
                        $fatal(1, "row boundary mismatch at byte %0d: pos=%0d",
                               byte_index, dut.row_byte_pos);
                end
                sd_sec_read_data_valid = 1'b0;
            end
            @(negedge clk);
            sd_sec_read_end = 1'b1;
            @(negedge clk);
            sd_sec_read_end = 1'b0;
        end
    endtask

    task automatic start_load;
        begin
            @(negedge clk);
            load_start = 1'b1;
            @(negedge clk);
            load_start = 1'b0;
            wait (sd_sec_read);
        end
    endtask

    task automatic send_short_sector;
        integer byte_index;
        begin
            for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1) begin
                @(negedge clk);
                sd_sec_read_data = bmp_byte(byte_index);
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

    task automatic reject_invalid_header;
        integer errors_before;
        begin
            errors_before = load_error_count;
            start_load();
            send_sector();
            repeat (3) @(posedge clk);
            if (!ready || write_req || state_code != 4'hE)
                $fatal(1, "invalid BMP header was accepted");
            if (load_error_count != errors_before + 1)
                $fatal(1, "invalid BMP header did not report one load error");
        end
    endtask

    bmp_read #(
        .SD_PROGRESS_TIMEOUT_CYCLES(32)
    ) dut (
        .clk(clk),
        .rst(rst),
        .ready(ready),
        .scan_start(scan_start),
        .scan_start_sector(32'd0),
        .scan_max_sector(32'd100),
        .scan_target_count(4'd8),
        .scan_done(scan_done),
        .scan_found_valid(scan_found_valid),
        .scan_found_sector(),
        .scan_found_total(scan_found_total),
        .scan_found_voice(scan_found_voice),
        .scan_found_voice_offset(scan_found_voice_offset),
        .load_start(load_start),
        .load_sector(32'd7),
        .load_error_pulse(load_error_pulse),
        .sd_recover_pulse(sd_recover_pulse),
        .sd_init_done(sd_init_done),
        .state_code(state_code),
        .bmp_width(16'd8),
        .bmp_height(16'd6),
        .source_width(source_width),
        .source_height(source_height),
        .write_req(write_req),
        .write_req_ack(write_req_ack),
        .source_start(source_start),
        .sd_sec_read(sd_sec_read),
        .sd_sec_read_addr(),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),
        .sd_sec_read_error(1'b0),
        .bmp_data_wr_en(bmp_data_wr_en),
        .bmp_data(bmp_data)
    );

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        sd_init_done = 1'b1;
        start_load();
        send_sector();
        wait (write_req);
        if (source_width != 16'd5 || source_height != 16'd3)
            $fatal(1, "scaled BMP dimensions were not exposed");

        @(negedge clk);
        write_req_ack = 1'b1;
        wait (!write_req);
        @(negedge clk);
        write_req_ack = 1'b0;

        // Pixel reread must remain stopped until the scaler has finished any
        // leading border and explicitly releases the source stream.
        repeat (4) @(negedge clk);
        if (sd_sec_read)
            $fatal(1, "BMP pixel stream started before source_start");
        source_start = 1'b1;
        @(negedge clk);
        source_start = 1'b0;

        wait (sd_sec_read);
        send_sector();
        wait (ready);
        repeat (2) @(posedge clk);

        if (captured_count != 15)
            $fatal(1, "row padding changed pixel count: %0d", captured_count);
        for (pixel = 0; pixel < 15; pixel = pixel + 1) begin
            if (captured[pixel] !==
                {8'h80 + pixel[7:0], 8'h40 + pixel[7:0], pixel[7:0]})
                $fatal(1, "pixel %0d mismatch: %h", pixel, captured[pixel]);
        end

        // The stability reference recommends rejecting malformed BMP headers
        // before requesting a frame buffer. Cover the fields that the former
        // BM/size-only check did not validate.
        header_planes = 8'd2;
        reject_invalid_header();

        header_planes = 8'd1;
        header_dib_size = 8'd12;
        reject_invalid_header();

        header_dib_size = 8'd40;
        header_pixel_offset = 8'd40;
        reject_invalid_header();

        header_pixel_offset = 8'd54;
        header_file_len = 8'd54;
        reject_invalid_header();

        header_file_len = 8'd101;
        reject_invalid_header();

        // Reinitialize the same parser and prove that the widened scan count
        // reaches eight instead of wrapping to zero after the seventh hit.
        @(negedge clk);
        rst = 1'b1;
        header_file_len = 8'd118;
        header_dib_size = 8'd40;
        header_pixel_offset = 8'd54;
        header_planes = 8'd1;
        scan_found_pulses = 0;
        scan_voice_pulses = 0;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        sd_init_done = 1'b1;
        @(negedge clk);
        scan_start = 1'b1;
        @(negedge clk);
        scan_start = 1'b0;
        for (scan_index = 0; scan_index < 8; scan_index = scan_index + 1) begin
            wait (sd_sec_read);
            send_sector();
        end
        wait (scan_done);
        repeat (2) @(posedge clk);
        if (scan_found_total != 4'd8 || scan_found_pulses != 8)
            $fatal(1, "eight-image scan count failed: total=%0d pulses=%0d",
                   scan_found_total, scan_found_pulses);
        if (scan_voice_pulses != 8 || scan_found_voice_offset != 32'd102)
            $fatal(1, "embedded narration trailer was not discovered");

        // A controller that ends a sector early must not leave stale header
        // bytes in the parser. It is rejected and requests a full SD restart.
        @(negedge clk);
        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        sd_init_done = 1'b1;
        start_load();
        send_short_sector();
        wait (ready);
        repeat (2) @(posedge clk);
        if (recover_count != 1 || load_error_count == 0 || state_code != 4'hE)
            $fatal(1, "short sector did not trigger bounded recovery");

        // A missing data token formerly held sd_sec_read forever. The progress
        // watchdog must return to IDLE and pulse the shared SD-stack reset.
        @(negedge clk);
        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        sd_init_done = 1'b1;
        start_load();
        wait (sd_recover_pulse);
        repeat (2) @(posedge clk);
        if (!ready || recover_count != 2 || state_code != 4'hE)
            $fatal(1, "stalled SD read did not time out and recover");

        $display("TEST_PASS tb_bmp_read_scaling");
        $finish;
    end

    initial begin
        #400000;
        $fatal(1, "test timeout");
    end
endmodule
