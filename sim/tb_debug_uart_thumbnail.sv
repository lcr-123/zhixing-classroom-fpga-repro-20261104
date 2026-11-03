`timescale 1ns/1ps

module tb_debug_uart_thumbnail;
    localparam integer CLK_FRE = 10;
    localparam integer BAUD_RATE = 1000000;
    localparam integer BIT_TIME_NS = 1000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg uart_rx = 1'b1;
    wire uart_tx;
    reg [7:0] payload [0:255];
    integer payload_length;
    reg [7:0] packet_type;
    reg [15:0] packet_sequence;
    wire thumbnail_request_toggle;
    wire [12:0] thumbnail_read_addr;
    reg thumbnail_done_toggle = 1'b0;
    reg [15:0] thumbnail_frame_id = 16'd0;
    reg [31:0] thumbnail_crc32 = 32'd0;
    reg [15:0] thumbnail_read_data = 16'd0;
    integer chunk;
    integer pixel;

    always #50 clk = ~clk;
    always @(posedge clk)
        thumbnail_read_data <= {thumbnail_read_addr[7:0] ^ 8'hA5,
                                thumbnail_read_addr[7:0]};

    function automatic [15:0] crc16_next;
        input [15:0] crc;
        input [7:0] data;
        integer i;
        reg [15:0] value;
        begin
            value = crc ^ {data, 8'h00};
            for (i = 0; i < 8; i = i + 1)
                value = value[15] ? (value << 1) ^ 16'h1021 : value << 1;
            crc16_next = value;
        end
    endfunction

    task automatic send_byte;
        input [7:0] value;
        integer i;
        begin
            uart_rx = 1'b0;
            #(BIT_TIME_NS);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = value[i];
                #(BIT_TIME_NS);
            end
            uart_rx = 1'b1;
            #(BIT_TIME_NS);
        end
    endtask

    task automatic receive_byte;
        output [7:0] value;
        integer i;
        begin
            @(negedge uart_tx);
            #(BIT_TIME_NS + BIT_TIME_NS/2);
            for (i = 0; i < 8; i = i + 1) begin
                value[i] = uart_tx;
                #(BIT_TIME_NS);
            end
            if (!uart_tx)
                $fatal(1, "UART stop bit low");
        end
    endtask

    task automatic send_command;
        input [7:0] msg_type;
        input [15:0] sequence_id;
        reg [15:0] crc;
        begin
            crc = 16'hFFFF;
            send_byte(8'hA5);
            send_byte(8'h5A);
            send_byte(8'h01); crc = crc16_next(crc, 8'h01);
            send_byte(msg_type); crc = crc16_next(crc, msg_type);
            send_byte(8'h00); crc = crc16_next(crc, 8'h00);
            send_byte(sequence_id[7:0]); crc = crc16_next(crc, sequence_id[7:0]);
            send_byte(sequence_id[15:8]); crc = crc16_next(crc, sequence_id[15:8]);
            send_byte(8'h00); crc = crc16_next(crc, 8'h00);
            send_byte(8'h00); crc = crc16_next(crc, 8'h00);
            send_byte(crc[7:0]);
            send_byte(crc[15:8]);
        end
    endtask

    task automatic receive_packet;
        reg [7:0] value;
        reg [7:0] version;
        reg [7:0] flags;
        reg [7:0] length_low;
        reg [7:0] length_high;
        reg [7:0] crc_low;
        reg [7:0] crc_high;
        reg [15:0] crc;
        integer i;
        begin
            receive_byte(value);
            if (value != 8'hA5) $fatal(2, "bad sync 0");
            receive_byte(value);
            if (value != 8'h5A) $fatal(3, "bad sync 1");
            crc = 16'hFFFF;
            receive_byte(version); crc = crc16_next(crc, version);
            receive_byte(packet_type); crc = crc16_next(crc, packet_type);
            receive_byte(flags); crc = crc16_next(crc, flags);
            receive_byte(value); packet_sequence[7:0] = value; crc = crc16_next(crc, value);
            receive_byte(value); packet_sequence[15:8] = value; crc = crc16_next(crc, value);
            receive_byte(length_low); crc = crc16_next(crc, length_low);
            receive_byte(length_high); crc = crc16_next(crc, length_high);
            payload_length = {length_high, length_low};
            if (version != 8'h01 || payload_length > 256)
                $fatal(4, "bad packet header");
            for (i = 0; i < payload_length; i = i + 1) begin
                receive_byte(payload[i]);
                crc = crc16_next(crc, payload[i]);
            end
            receive_byte(crc_low);
            receive_byte(crc_high);
            if ({crc_high, crc_low} != crc)
                $fatal(5, "bad packet CRC");
        end
    endtask

    debug_uart #(
        .CLK_FRE(CLK_FRE),
        .BAUD_RATE(BAUD_RATE),
        .STATUS_INTERVAL_CYCLES(2000000)
    ) dut (
        .clk(clk), .rst_n(rst_n), .state_code(4'd0),
        .display_valid(1'b1), .sdram_init_done(1'b1),
        .sdram_refresh_active(1'b0), .sdram_busy(1'b0),
        .audio_pll_lock(1'b1), .audio_valid(1'b1), .axis_ready(1'b1),
        .write_buf_idx(2'd0), .disp_buf_idx(2'd0),
        .video_brightness(), .video_contrast(),
        .video_osd_enable(), .video_subtitle_enable(),
        .video_control_toggle(),
        .thumbnail_request_toggle(thumbnail_request_toggle),
        .thumbnail_done_toggle(thumbnail_done_toggle),
        .thumbnail_frame_id(thumbnail_frame_id),
        .thumbnail_crc32(thumbnail_crc32),
        .thumbnail_read_addr(thumbnail_read_addr),
        .thumbnail_read_data(thumbnail_read_data),
        .uart_rx_pin(uart_rx), .uart_tx_pin(uart_tx)
    );

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        receive_packet();
        if (packet_type != 8'h01)
            $fatal(6, "HELLO missing");

        send_command(8'h87, 16'h3456);
        wait (thumbnail_request_toggle == 1'b1);
        repeat (5) @(posedge clk);
        thumbnail_frame_id = 16'h2468;
        thumbnail_crc32 = 32'h89ABCDEF;
        thumbnail_done_toggle = 1'b1;

        receive_packet();
        if (packet_type != 8'h10 || payload_length != 12 ||
            payload[0] != 80 || payload[2] != 60 || payload[4] != 1 ||
            {payload[7], payload[6]} != 16'h2468 ||
            {payload[11], payload[10], payload[9], payload[8]} != 32'd9600)
            $fatal(7, "IMAGE_BEGIN mismatch");

        for (chunk = 0; chunk < 40; chunk = chunk + 1) begin
            receive_packet();
            if (packet_type != 8'h11 || payload_length != 244 ||
                {payload[1], payload[0]} != 16'h2468 ||
                {payload[3], payload[2]} != chunk)
                $fatal(8, "IMAGE_DATA header mismatch at chunk %0d", chunk);
            for (pixel = 0; pixel < 120; pixel = pixel + 1) begin
                if (payload[4 + pixel * 2] != ((chunk * 120 + pixel) & 8'hFF) ||
                    payload[5 + pixel * 2] !=
                        (((chunk * 120 + pixel) & 8'hFF) ^ 8'hA5))
                    $fatal(9, "IMAGE_DATA pixel mismatch at %0d",
                           chunk * 120 + pixel);
            end
        end

        receive_packet();
        if (packet_type != 8'h12 || payload_length != 10 ||
            {payload[1], payload[0]} != 16'h2468 ||
            {payload[5], payload[4], payload[3], payload[2]} != 32'h89ABCDEF)
            $fatal(10, "IMAGE_END mismatch");

        $display("TEST_PASS tb_debug_uart_thumbnail");
        $finish;
    end
endmodule
