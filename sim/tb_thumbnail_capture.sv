`timescale 1ns/1ps

module tb_thumbnail_capture #(
    parameter integer SOURCE_WIDTH = 16,
    parameter integer SOURCE_HEIGHT = 8,
    parameter integer SAMPLE_SHIFT = 1
);
    localparam integer THUMB_WIDTH = SOURCE_WIDTH >> SAMPLE_SHIFT;
    localparam integer THUMB_HEIGHT = SOURCE_HEIGHT >> SAMPLE_SHIFT;
    localparam integer PIXELS = THUMB_WIDTH * THUMB_HEIGHT;
    localparam integer ADDR_WIDTH = $clog2(PIXELS);

    reg pixel_clk = 1'b0;
    reg read_clk = 1'b0;
    reg pixel_rst = 1'b1;
    reg video_user = 1'b0;
    reg video_valid = 1'b0;
    reg [23:0] video_rgb = 24'd0;
    reg request_toggle = 1'b0;
    wire done_toggle;
    wire [15:0] frame_id;
    wire [31:0] frame_crc32;
    reg [ADDR_WIDTH-1:0] read_addr = 0;
    wire [15:0] read_data;

    integer x;
    integer y;
    integer i;
    reg [15:0] expected;
    reg [31:0] expected_crc;

    always #5 pixel_clk = ~pixel_clk;
    always #7 read_clk = ~read_clk;

    function automatic [15:0] pattern565;
        input integer px;
        input integer py;
        reg [7:0] red;
        reg [7:0] green;
        reg [7:0] blue;
        begin
            // Mix high coordinate bits so bank-selection faults cannot hide
            // behind an image that repeats every few sampled pixels.
            red = (px * 13) ^ (py * 7) ^ (px >> 5);
            green = (py * 19) ^ (px * 3) ^ (py >> 3);
            blue = (px * 5) ^ (py * 11) ^ (px >> 8);
            pattern565 = {red[7:3], green[7:2], blue[7:3]};
        end
    endfunction

    function automatic [31:0] crc32_byte;
        input [31:0] crc;
        input [7:0] data;
        integer bit_index;
        reg [31:0] value;
        begin
            value = crc ^ data;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                value = value[0] ? (value >> 1) ^ 32'hEDB88320 : value >> 1;
            crc32_byte = value;
        end
    endfunction

    task automatic send_frame;
        begin
            for (y = 0; y < SOURCE_HEIGHT; y = y + 1) begin
                for (x = 0; x < SOURCE_WIDTH; x = x + 1) begin
                    @(negedge pixel_clk);
                    video_valid = 1'b1;
                    video_user = (x == 0) && (y == 0);
                    video_rgb[23:16] = (x * 13) ^ (y * 7) ^ (x >> 5);
                    video_rgb[15:8] = (y * 19) ^ (x * 3) ^ (y >> 3);
                    video_rgb[7:0] = (x * 5) ^ (y * 11) ^ (x >> 8);
                end
                @(negedge pixel_clk);
                video_valid = 1'b0;
                video_user = 1'b0;
                repeat (2) @(negedge pixel_clk);
            end
        end
    endtask

    thumbnail_capture_bram #(
        .SOURCE_WIDTH(SOURCE_WIDTH),
        .SOURCE_HEIGHT(SOURCE_HEIGHT),
        .SAMPLE_SHIFT(SAMPLE_SHIFT),
        .THUMB_WIDTH(THUMB_WIDTH),
        .THUMB_HEIGHT(THUMB_HEIGHT),
        .PIXELS(PIXELS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .pixel_clk(pixel_clk),
        .pixel_rst(pixel_rst),
        .video_user(video_user),
        .video_valid(video_valid),
        .video_rgb(video_rgb),
        .request_toggle(request_toggle),
        .done_toggle(done_toggle),
        .frame_id(frame_id),
        .frame_crc32(frame_crc32),
        .read_clk(read_clk),
        .read_addr(read_addr),
        .read_data(read_data)
    );

    initial begin
        repeat (5) @(posedge pixel_clk);
        pixel_rst = 1'b0;
        request_toggle = 1'b1;
        repeat (5) @(posedge pixel_clk);
        send_frame();

        wait (done_toggle == 1'b1);
        if (frame_id != 16'd1)
            $fatal(1, "frame id mismatch");

        expected_crc = 32'hFFFFFFFF;
        for (y = 0; y < THUMB_HEIGHT; y = y + 1) begin
            for (x = 0; x < THUMB_WIDTH; x = x + 1) begin
                expected = pattern565(x << SAMPLE_SHIFT, y << SAMPLE_SHIFT);
                expected_crc = crc32_byte(expected_crc, expected[7:0]);
                expected_crc = crc32_byte(expected_crc, expected[15:8]);
            end
        end
        if (frame_crc32 != ~expected_crc)
            $fatal(2, "frame CRC mismatch: got %08x expected %08x",
                   frame_crc32, ~expected_crc);

        // Capture the same pixels again without resetting the DUT.  Each
        // thumbnail must restart CRC32 from 0xFFFFFFFF; this catches accidental
        // reuse of the previous frame's internal accumulator.
        request_toggle = 1'b0;
        repeat (5) @(posedge pixel_clk);
        send_frame();

        wait (done_toggle == 1'b0);
        if (frame_id != 16'd2)
            $fatal(3, "second frame id mismatch");
        if (frame_crc32 != ~expected_crc)
            $fatal(4, "second frame CRC mismatch: got %08x expected %08x",
                   frame_crc32, ~expected_crc);

        for (i = 0; i < PIXELS; i = i + 1) begin
            @(negedge read_clk);
            read_addr = i;
            @(posedge read_clk);
            #1;
            expected = pattern565((i % THUMB_WIDTH) << SAMPLE_SHIFT,
                                  (i / THUMB_WIDTH) << SAMPLE_SHIFT);
            if (read_data != expected)
                $fatal(5, "pixel %0d mismatch: got %04x expected %04x",
                       i, read_data, expected);
        end

        // Abrupt address changes across banks must still return the requested
        // word after exactly one read edge, including the partial last bank.
        for (i = PIXELS - 1; i >= 0; i = i - 1) begin
            @(negedge read_clk);
            read_addr = i;
            @(posedge read_clk);
            #1;
            expected = pattern565((i % THUMB_WIDTH) << SAMPLE_SHIFT,
                                  (i / THUMB_WIDTH) << SAMPLE_SHIFT);
            if (read_data != expected)
                $fatal(6, "reverse pixel %0d mismatch", i);
        end
        if (PIXELS < (1 << ADDR_WIDTH)) begin
            @(negedge read_clk);
            read_addr = PIXELS;
            @(posedge read_clk);
            #1;
            if (read_data !== 16'd0)
                $fatal(7, "out-of-range read was not zero");
        end

        $display("TEST_PASS tb_thumbnail_capture");
        $finish;
    end
endmodule
