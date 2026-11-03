`timescale 1ns/1ps

module tb_debug_uart;
    localparam integer CLK_FRE = 10;
    localparam integer BAUD_RATE = 1000000;
    localparam integer BIT_TIME_NS = 1000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg uart_rx = 1'b1;
    reg [12:0] sd_debug_event_toggle = 13'd0;
    reg video_commit_toggle = 1'b0;
    wire uart_tx;
    reg [7:0] payload [0:31];
    integer payload_length;
    reg [7:0] packet_type;
    reg [7:0] packet_flags;
    reg [15:0] packet_sequence;
    wire thumbnail_request_toggle;
    wire [12:0] thumbnail_read_addr;
    wire signed [2:0] video_brightness;
    wire [1:0] video_contrast;
    wire video_osd_enable;
    wire video_subtitle_enable;
    wire video_control_toggle;

    always #50 clk = ~clk;

    function automatic [15:0] crc16_next;
        input [15:0] crc;
        input [7:0] data;
        integer i;
        reg [15:0] value;
        begin
            value = crc ^ {data, 8'h00};
            for (i = 0; i < 8; i = i + 1) begin
                if (value[15])
                    value = (value << 1) ^ 16'h1021;
                else
                    value = value << 1;
            end
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

    task automatic send_command_byte;
        input [7:0] msg_type;
        input [15:0] sequence_id;
        input [7:0] payload_byte;
        reg [15:0] crc;
        begin
            crc = 16'hFFFF;
            send_byte(8'hA5);
            send_byte(8'h5A);
            send_byte(8'h01); crc = crc16_next(crc, 8'h01);
            send_byte(msg_type); crc = crc16_next(crc, msg_type);
            send_byte(8'h00); crc = crc16_next(crc, 8'h00);
            send_byte(sequence_id[7:0]);
            crc = crc16_next(crc, sequence_id[7:0]);
            send_byte(sequence_id[15:8]);
            crc = crc16_next(crc, sequence_id[15:8]);
            send_byte(8'h01); crc = crc16_next(crc, 8'h01);
            send_byte(8'h00); crc = crc16_next(crc, 8'h00);
            send_byte(payload_byte);
            crc = crc16_next(crc, payload_byte);
            send_byte(crc[7:0]);
            send_byte(crc[15:8]);
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

    task automatic send_bad_crc_ping;
        input [15:0] sequence_id;
        reg [15:0] crc;
        begin
            crc = 16'hFFFF;
            send_byte(8'hA5);
            send_byte(8'h5A);
            send_byte(8'h01); crc = crc16_next(crc, 8'h01);
            send_byte(8'h80); crc = crc16_next(crc, 8'h80);
            send_byte(8'h00); crc = crc16_next(crc, 8'h00);
            send_byte(sequence_id[7:0]);
            crc = crc16_next(crc, sequence_id[7:0]);
            send_byte(sequence_id[15:8]);
            crc = crc16_next(crc, sequence_id[15:8]);
            send_byte(8'h00); crc = crc16_next(crc, 8'h00);
            send_byte(8'h00); crc = crc16_next(crc, 8'h00);
            send_byte(crc[7:0] ^ 8'h01);
            send_byte(crc[15:8]);
        end
    endtask

    task automatic receive_packet;
        reg [7:0] value;
        reg [7:0] version;
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
            receive_byte(packet_flags); crc = crc16_next(crc, packet_flags);
            receive_byte(value); packet_sequence[7:0] = value; crc = crc16_next(crc, value);
            receive_byte(value); packet_sequence[15:8] = value; crc = crc16_next(crc, value);
            receive_byte(length_low); crc = crc16_next(crc, length_low);
            receive_byte(length_high); crc = crc16_next(crc, length_high);
            payload_length = {length_high, length_low};
            if (version != 8'h01 || payload_length > 32)
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
        .STATUS_INTERVAL_CYCLES(1000000)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .state_code(4'hA),
        .app_state(4'd3),
        .app_target_image(4'd5),
        .sd_debug_event_toggle(sd_debug_event_toggle),
        .video_commit_toggle(video_commit_toggle),
        .display_valid(1'b1),
        .sdram_init_done(1'b1),
        .sdram_refresh_active(1'b0),
        .sdram_busy(1'b1),
        .audio_pll_lock(1'b1),
        .audio_valid(1'b0),
        .axis_ready(1'b1),
        .write_buf_idx(2'd2),
        .disp_buf_idx(2'd1),
        .video_brightness(video_brightness),
        .video_contrast(video_contrast),
        .video_osd_enable(video_osd_enable),
        .video_subtitle_enable(video_subtitle_enable),
        .video_control_toggle(video_control_toggle),
        .thumbnail_request_toggle(thumbnail_request_toggle),
        .thumbnail_done_toggle(1'b0),
        .thumbnail_frame_id(16'd0),
        .thumbnail_crc32(32'd0),
        .thumbnail_read_addr(thumbnail_read_addr),
        .thumbnail_read_data(16'd0),
        .uart_rx_pin(uart_rx),
        .uart_tx_pin(uart_tx)
    );

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1'b1;

        receive_packet();
        if (packet_type != 8'h01 || payload_length != 16 || payload[0] != 8'h01)
            $fatal(6, "HELLO mismatch");

        send_bad_crc_ping(16'hDEAD);
        send_command(8'h80, 16'h1234);
        receive_packet();
        if (packet_type != 8'h80 || packet_flags != 8'h01 ||
            packet_sequence != 16'h1234 || payload_length != 0)
            $fatal(7, "PING response mismatch");

        sd_debug_event_toggle = 13'h1188;
        video_commit_toggle = 1'b1;
        repeat (8) @(posedge clk);
        send_command(8'h81, 16'h2345);
        receive_packet();
        if (packet_type != 8'h02 || payload_length != 20 ||
            payload[0] != 8'h0A || payload[1] != 8'h5B ||
            payload[2] != 8'h02 || payload[3] != 8'h01 ||
            payload[4] != 8'd3 || payload[5] != 8'd5 ||
            payload[9] != 8'd1 || payload[13] != 8'd1 ||
            payload[14] != 8'd1 || payload[18] != 8'd1 ||
            payload[19] != 8'd1)
            $fatal(8, "STATUS mismatch");

        send_command_byte(8'h84, 16'h3456, 8'hFE);
        receive_packet();
        if (packet_type != 8'h84 || packet_flags != 8'h01 ||
            packet_sequence != 16'h3456 || payload_length != 0 ||
            video_brightness !== -3'sd2 || video_control_toggle != 1'b1)
            $fatal(9, "SET_BRIGHTNESS mismatch");

        send_command_byte(8'h85, 16'h4567, 8'h03);
        receive_packet();
        if (packet_type != 8'h85 || packet_flags != 8'h01 ||
            packet_sequence != 16'h4567 || video_contrast != 2'd3 ||
            video_control_toggle != 1'b0)
            $fatal(10, "SET_CONTRAST mismatch");

        send_command_byte(8'h86, 16'h5678, 8'h01);
        receive_packet();
        if (packet_type != 8'h86 || packet_flags != 8'h01 ||
            packet_sequence != 16'h5678 || !video_osd_enable ||
            video_subtitle_enable || video_control_toggle != 1'b1)
            $fatal(11, "SET_OSD mismatch");

        $display("TEST_PASS tb_debug_uart");
        $finish;
    end
endmodule
