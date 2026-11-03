`timescale 1ns/1ps

module tb_lesson_voice_reader;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;
    reg stop = 1'b0;
    reg buffer_ready = 1'b1;
    reg [7:0] sd_data = 8'd0;
    reg sd_valid = 1'b0;
    reg sd_end = 1'b0;
    reg sd_error = 1'b0;
    wire busy;
    wire voice_start_pulse;
    wire voice_end_pulse;
    wire voice_error_pulse;
    wire sd_recover_pulse;
    wire [1:0] voice_page;
    wire [31:0] voice_sample_total;
    wire voice_data_valid;
    wire [7:0] voice_data;
    wire sd_read;
    wire [31:0] sd_addr;

    integer captured_count = 0;
    reg [7:0] captured [0:31];
    integer start_count = 0;
    integer end_count = 0;
    integer error_count = 0;
    integer recover_count = 0;
    reg [31:0] header_sample_count = 32'd5;
    integer invalid_case;
    integer fault_case;
    integer fault_index;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (voice_data_valid) begin
            captured[captured_count] <= voice_data;
            captured_count <= captured_count + 1;
        end
        if (voice_start_pulse)
            start_count <= start_count + 1;
        if (voice_end_pulse)
            end_count <= end_count + 1;
        if (voice_error_pulse)
            error_count <= error_count + 1;
        if (sd_recover_pulse)
            recover_count <= recover_count + 1;
    end

    function automatic [7:0] sector_byte;
        input [31:0] address;
        input integer index;
        integer relative;
        begin
            sector_byte = 8'd0;
            if (address == 32'd100)
                relative = index - 510;
            else
                relative = index + 2;

            case (relative)
                0: sector_byte = "L";
                1: sector_byte = "M";
                2: sector_byte = "V";
                3: sector_byte = "1";
                4: sector_byte = 8'd2;
                5: sector_byte = 8'd1;
                6: sector_byte = 8'h80;
                7: sector_byte = 8'h3e;
                8: sector_byte = header_sample_count[7:0];
                9: sector_byte = header_sample_count[15:8];
                10: sector_byte = header_sample_count[23:16];
                11: sector_byte = header_sample_count[31:24];
                16: sector_byte = 8'h11;
                17: sector_byte = 8'h22;
                18: sector_byte = 8'h80;
                19: sector_byte = 8'hfe;
                20: sector_byte = 8'h7f;
                default: sector_byte = 8'd0;
            endcase
        end
    endfunction

    task automatic send_requested_sector;
        integer index;
        reg [31:0] address;
        begin
            wait (sd_read);
            address = sd_addr;
            for (index = 0; index < 512; index = index + 1) begin
                @(negedge clk);
                sd_data = sector_byte(address, index);
                sd_valid = 1'b1;
                @(negedge clk);
                sd_valid = 1'b0;
            end
            @(negedge clk);
            sd_end = 1'b1;
            @(negedge clk);
            sd_end = 1'b0;
        end
    endtask

    // No idle clocks between data beats: header decode must work for a
    // continuous producer as well as the ordinary sparse SD byte stream.
    task automatic send_requested_sector_burst;
        integer index;
        reg [31:0] address;
        begin
            wait (sd_read);
            address = sd_addr;
            for (index = 0; index < 512; index = index + 1) begin
                @(negedge clk);
                sd_data = sector_byte(address, index);
                sd_valid = 1'b1;
            end
            @(negedge clk);
            sd_valid = 1'b0;
            sd_end = 1'b1;
            @(negedge clk);
            sd_end = 1'b0;
        end
    endtask

    task automatic send_short_requested_sector;
        integer index;
        begin
            wait (sd_read);
            for (index = 0; index < 16; index = index + 1) begin
                @(negedge clk);
                sd_data = 8'd0;
                sd_valid = 1'b1;
                @(negedge clk);
                sd_valid = 1'b0;
            end
            @(negedge clk);
            sd_end = 1'b1;
            @(negedge clk);
            sd_end = 1'b0;
        end
    endtask

    lesson_voice_reader #(
        .SD_PROGRESS_TIMEOUT_CYCLES(32)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .stop(stop),
        .bmp_sector(32'd99),
        .voice_byte_offset(32'd1022),
        .expected_page(2'd2),
        .buffer_ready(buffer_ready),
        .ready(),
        .busy(busy),
        .voice_start_pulse(voice_start_pulse),
        .voice_end_pulse(voice_end_pulse),
        .voice_error_pulse(voice_error_pulse),
        .sd_recover_pulse(sd_recover_pulse),
        .voice_page(voice_page),
        .voice_sample_total(voice_sample_total),
        .voice_data_valid(voice_data_valid),
        .voice_data(voice_data),
        .sd_sec_read(sd_read),
        .sd_sec_read_addr(sd_addr),
        .sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(sd_valid),
        .sd_sec_read_end(sd_end),
        .sd_sec_read_error(sd_error)
    );

    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        if (!busy || sd_addr != 32'd100)
            $fatal(1, "reader did not jump to the embedded trailer sector");
        send_requested_sector();

        buffer_ready = 1'b0;
        repeat (20) @(posedge clk);
        if (sd_read || sd_addr != 32'd101)
            $fatal(2, "reader did not pause between sectors for FIFO space");
        buffer_ready = 1'b1;
        send_requested_sector();

        wait (!busy);
        repeat (3) @(posedge clk);
        if (voice_sample_total != 32'd5)
            $fatal(10, "LMV1 sample count mailbox incorrect: %0d",
                   voice_sample_total);
        if (start_count != 1 || end_count != 1 || error_count != 0)
            $fatal(3, "voice start/end/error event counts are wrong");
        if (voice_page != 2'd2 || captured_count != 5)
            $fatal(4, "voice metadata or payload length is wrong");
        if (captured[0] != 8'h11 || captured[1] != 8'h22 ||
            captured[2] != 8'h80 || captured[3] != 8'hfe ||
            captured[4] != 8'h7f)
            $fatal(5, "voice payload bytes are out of order");

        header_sample_count = 8'd1;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        send_requested_sector();
        send_requested_sector();
        wait (!busy);
        repeat (3) @(posedge clk);
        if (captured_count != 6 || captured[5] != 8'h11 ||
            start_count != 2 || end_count != 2 || error_count != 0)
            $fatal(9, "single-byte narration payload boundary failed");
        header_sample_count = 32'd5;

        // Width reduction must never accept an invalid 32-bit count after
        // truncating its high bits.  Rejected headers emit no PCM/start.
        for (invalid_case = 0; invalid_case < 4; invalid_case = invalid_case + 1) begin
            case (invalid_case)
                0: header_sample_count = 32'd0;
                1: header_sample_count = 32'd4000001;
                2: header_sample_count = 32'h00400001;
                3: header_sample_count = 32'h80000001;
            endcase
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            send_requested_sector_burst();
            send_requested_sector_burst();
            wait (!busy);
            repeat (3) @(posedge clk);
            if (captured_count != 6 || start_count != 2 || end_count != 2 ||
                error_count != invalid_case + 1 || recover_count != 0)
                $fatal(11, "invalid 32-bit length accepted: %h", header_sample_count);
        end

        // Starting again must clear the saturated header cursor and flags.
        header_sample_count = 32'd5;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        send_requested_sector_burst();
        send_requested_sector_burst();
        wait (!busy);
        repeat (3) @(posedge clk);
        if (captured_count != 11 || start_count != 3 || end_count != 3 ||
            captured[6] != 8'h11 || captured[10] != 8'h7f || error_count != 4)
            $fatal(12, "continuous payload or header cursor restart failed");

        // A short sector is not a valid transfer even if an end pulse arrives.
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        send_short_requested_sector();
        wait (!busy);
        repeat (2) @(posedge clk);
        if (recover_count != 1 || error_count != 5)
            $fatal(6, "short narration sector was accepted");

        // A missing SD data token must release ownership instead of blocking
        // every later image request behind a permanently busy narration read.
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait (sd_recover_pulse);
        repeat (2) @(posedge clk);
        if (busy || recover_count != 2 || error_count != 6)
            $fatal(7, "stalled narration read did not recover");

        // A controller error on the last header beat or first payload beat
        // must suppress commit even though the private count pipeline runs.
        // Restart immediately with a fresh header and verify all five bytes.
        for (fault_case = 0; fault_case < 2; fault_case = fault_case + 1) begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            send_requested_sector_burst();
            wait (sd_read);
            for (fault_index = 0; fault_index <= 13 + fault_case;
                 fault_index = fault_index + 1) begin
                @(negedge clk);
                sd_data = sector_byte(32'd101, fault_index);
                sd_valid = 1'b1;
                sd_error = (fault_index == 13 + fault_case);
            end
            @(negedge clk);
            sd_valid = 1'b0;
            sd_error = 1'b0;
            repeat (3) @(negedge clk);
            if (busy || captured_count != 11 + 5 * fault_case ||
                start_count != 3 + fault_case || end_count != 3 + fault_case ||
                error_count != 7 + fault_case || recover_count != 3 + fault_case)
                $fatal(13, "fault beat committed stale header/payload: %0d", fault_case);

            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            send_requested_sector_burst();
            send_requested_sector_burst();
            wait (!busy);
            repeat (3) @(negedge clk);
            if (captured_count != 16 + 5 * fault_case ||
                start_count != 4 + fault_case || end_count != 4 + fault_case ||
                captured[11 + 5 * fault_case] != 8'h11 ||
                captured[15 + 5 * fault_case] != 8'h7f || voice_sample_total != 32'd5)
                $fatal(14, "header pipeline fault restart failed: %0d", fault_case);
        end

        $display("TEST_PASS tb_lesson_voice_reader");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(8, "test timeout");
    end
endmodule
