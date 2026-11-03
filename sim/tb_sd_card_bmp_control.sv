`timescale 1ns/1ps

module tb_sd_card_bmp_control #(parameter HOME_TEST = 0, parameter PREFETCH_TEST = 0);
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg key_next = 1'b1;
    reg key_auto = 1'b1;
    reg home_request = 1'b0;
    reg image_request = 1'b0;
    reg [3:0] image_request_idx = 4'd0;
    reg [2:0] image_request_zoom = 3'd2;
    reg image_request_prev = 1'b0;
    reg image_request_settings = 1'b0;
    reg prefetch_enable = 1'b0;
    reg [3:0] prefetch_image_idx = 4'd3;
    reg zoom_request = 1'b0;
    reg [2:0] zoom_level = 3'd2;
    reg [3:0] zoom_image_idx = 4'd0;
    reg narration_enable = 1'b0;
    reg write_finish_toggle = 1'b0;
    reg display_commit_ack_toggle = 1'b0;
    wire [1:0] write_buf_idx;
    wire [1:0] disp_buf_idx;
    wire [3:0] display_image_idx;
    wire display_page_right;
    wire display_settings_entry;
    wire [12:0] debug_event_toggle;
    wire auto_play_active;
    wire content_ready;
    wire [2:0] display_zoom_level;
    wire display_valid;
    wire display_commit_toggle;
    integer load_count = 0;
    integer voice_launch_count = 0;
    reg saved_voice_stop;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (dut.load_start_pulse)
            load_count <= load_count + 1;
        if (dut.voice_start_pulse)
            voice_launch_count <= voice_launch_count + 1;
    end

    task automatic report_found;
        input [3:0] index;
        begin
            @(negedge clk);
            dut.u_fat32_volume_scanner.file_found_index = index;
            dut.u_fat32_volume_scanner.file_found_cluster = 32'd20 + index;
            dut.u_fat32_volume_scanner.file_found_size =
                (index < 4'd3) ? 32'd1000000 : 32'd921654;
            dut.u_fat32_volume_scanner.file_found_valid = 1'b1;
            @(negedge clk);
            dut.u_fat32_volume_scanner.file_found_valid = 1'b0;
        end
    endtask

    task automatic finish_scan;
        begin
            @(negedge clk);
            dut.u_fat32_volume_scanner.state = 5'd0;
            dut.u_fat32_volume_scanner.sd_sec_read = 1'b0;
            dut.u_fat32_volume_scanner.done = 1'b1;
            @(negedge clk);
            dut.u_fat32_volume_scanner.done = 1'b0;
        end
    endtask

    sd_card_bmp #(
        .CLK_FREQ_HZ(1000),
        .SCAN_MAX_SECTOR(32'd100),
        .SCAN_TARGET_COUNT(4'd12),
        .AUTO_PLAY_ENABLE(1'b1),
        .PREFETCH_ENABLE(PREFETCH_TEST)
    ) dut (
        .clk(clk),
        .rst(rst),
        .key_next(key_next),
        .key_auto(key_auto),
        .home_request(home_request),
        .image_request(image_request),
        .image_request_idx(image_request_idx),
        .image_request_zoom(image_request_zoom),
        .image_request_prev(image_request_prev),
        .image_request_settings(image_request_settings),
        .prefetch_enable(prefetch_enable),
        .prefetch_image_idx(prefetch_image_idx),
        .zoom_request(zoom_request),
        .zoom_level(zoom_level),
        .zoom_image_idx(zoom_image_idx),
        .narration_enable(narration_enable),
        .voice_speed_level(2'd0),
        .voice_speed_toggle(1'b0),
        .voice_fifo_space_available(1'b1),
        .voice_fifo_empty(1'b1),
        .content_ready(content_ready),
        .state_code(),
        .display_image_idx(display_image_idx),
        .display_page_right(display_page_right),
        .display_settings_entry(display_settings_entry),
        .debug_event_toggle(debug_event_toggle),
        .auto_play_active(auto_play_active),
        .display_zoom_level(display_zoom_level),
        .bmp_width(16'd640),
        .bmp_height(16'd480),
        .display_valid(display_valid),
        .write_finish_toggle(write_finish_toggle),
        .write_buf_idx(write_buf_idx),
        .disp_buf_idx(disp_buf_idx),
        .display_commit_toggle(display_commit_toggle),
        .display_commit_ack_toggle(display_commit_ack_toggle),
        .write_req(),
        .write_req_ack(1'b0),
        .write_en(),
        .write_data(),
        .voice_fifo_write(),
        .voice_fifo_data(),
        .voice_start_toggle(),
        .voice_end_toggle(), .voice_stop_toggle(),
        .voice_clip_index(), .voice_sample_total(),
        .narration_busy(),
        .SD_nCS(),
        .SD_DCLK(),
        .SD_MOSI(),
        .SD_MISO(1'b1)
    );

    initial if (!HOME_TEST) begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        dut.sd_card_top_m0.sd_init_done = 1'b1;
        dut.bmp_read_m0.ready = 1'b1;

        // The real SD controller presents read_end for its single
        // S_READ_END cycle and returns to the request-wait state on the next
        // clock.  The consumer must see that handshake without an extra
        // pipeline delay, or its still-high request immediately rereads the
        // same sector and corrupts the BMP scan/load sequence.
        dut.u_fat32_virtual_sector_bridge.virtual_read_end = 1'b1;
        #1;
        if (!dut.bmp_sd_sec_read_end)
            $fatal(18, "BMP sector-end handshake was delayed");
        dut.u_fat32_virtual_sector_bridge.virtual_read_end = 1'b0;

        wait (dut.scan_start_pulse);
        dut.u_fat32_volume_scanner.state = 5'd0;
        dut.bmp_read_m0.ready = 1'b0;
        report_found(4'd0);
        report_found(4'd1);
        report_found(4'd2);
        report_found(4'd3);
        report_found(4'd4);
        report_found(4'd5);
        report_found(4'd6);
        report_found(4'd7);
        report_found(4'd8);
        report_found(4'd9);
        report_found(4'd10);
        report_found(4'd11);
        finish_scan();
        dut.bmp_read_m0.ready = 1'b1;
        @(posedge clk); #1;
        if (!content_ready)
            $fatal(1, "twelve-card content-ready gate did not assert");

        wait (load_count == 1);
        if (write_buf_idx != 2'd0 || debug_event_toggle[1:0] != 2'b11)
            $fatal(1, "first image did not target buffer 0");
        wait (dut.source_done_seen);
        @(negedge clk);
        write_finish_toggle = 1'b1;
        wait (display_commit_toggle == 1'b1);
        if (!debug_event_toggle[7])
            $fatal(20, "completed frame diagnostic event missing");
        if (!display_valid || disp_buf_idx != 2'd0 ||
            display_image_idx != 4'd0 ||
            !dut.display_commit_pending)
            $fatal(2, "first image commit request was not held");

        key_next = 1'b0;
        repeat (25) @(posedge clk);
        key_next = 1'b1;
        wait (dut.next_req_pending);
        repeat (8) @(posedge clk);
        if (load_count != 1)
            $fatal(3, "new load started before display commit ACK");

        display_commit_ack_toggle = 1'b1;
        wait (!dut.display_commit_pending);
        wait (load_count == 2);
        if (write_buf_idx != 2'd1 || dut.load_idx != 2'd1)
            $fatal(4, "manual next image did not use the alternate buffer");
        wait (dut.source_done_seen);
        @(negedge clk);
        write_finish_toggle = 1'b0;
        wait (display_commit_toggle == 1'b0);
        if (disp_buf_idx != 2'd1 || display_image_idx != 4'd1 ||
            !dut.display_commit_pending)
            $fatal(5, "second image commit request was not held");

        display_commit_ack_toggle = 1'b0;
        wait (!dut.display_commit_pending);

        // A home request must reload image zero into the alternate buffer and
        // wait for the same atomic frame-finish/commit handshake.
        @(negedge clk);
        home_request = 1'b1;
        @(negedge clk);
        home_request = 1'b0;
        wait (load_count == 3);
        if (write_buf_idx != 2'd0 || dut.load_idx != 2'd0 ||
            !debug_event_toggle[2])
            $fatal(6, "home request did not target image zero");
        wait (dut.source_done_seen);
        @(negedge clk);
        write_finish_toggle = 1'b1;
        wait (display_commit_toggle == 1'b1);
        if (disp_buf_idx != 2'd0 || display_image_idx != 4'd0 ||
            !dut.display_commit_pending)
            $fatal(7, "home image commit request was not held");
        display_commit_ack_toggle = 1'b1;
        wait (!dut.display_commit_pending);

        // Entering LEARN on an already displayed first page must launch that
        // page's embedded narration without a redundant image reload.
        @(negedge clk);
        narration_enable = 1'b1;
        image_request_idx = 4'd0;
        image_request = 1'b1;
        @(negedge clk);
        image_request = 1'b0;
        wait (voice_launch_count == 1);
        if (load_count != 3 || dut.selected_voice_idx != 2'd0)
            $fatal(18, "same-page narration caused a reload or wrong clip");
        @(negedge clk);
        narration_enable = 1'b0;

        // A zoom request rereads the current image into the inactive buffer;
        // the visible zoom changes only when that complete frame commits.
        @(negedge clk);
        zoom_level = 3'd0;
        zoom_image_idx = 4'd0;
        zoom_request = 1'b1;
        @(negedge clk);
        zoom_request = 1'b0;
        wait (load_count == 4);
        if (write_buf_idx != 2'd1 || dut.load_idx != 2'd0 ||
            dut.load_zoom_level != 3'd0 || display_zoom_level != 3'd2)
            $fatal(8, "zoom reload did not preserve image or atomic display state");
        wait (dut.source_done_seen);
        @(negedge clk);
        write_finish_toggle = 1'b0;
        wait (display_commit_toggle == 1'b0);
        if (display_zoom_level != 3'd0 || disp_buf_idx != 2'd1)
            $fatal(9, "zoom level did not commit with the alternate buffer");
        display_commit_ack_toggle = 1'b0;
        wait (!dut.display_commit_pending);

        key_auto = 1'b0;
        repeat (25) @(posedge clk);
        key_auto = 1'b1;
        wait (dut.auto_play_en);
        if (!auto_play_active)
            $fatal(6, "automatic playback status output did not assert");
        wait (load_count == 5);
        if (write_buf_idx != 2'd0 || dut.load_idx != 2'd1 ||
            dut.load_zoom_level != 3'd2)
            $fatal(10, "image one did not keep an independent default zoom");

        wait (dut.source_done_seen);
        @(negedge clk);
        write_finish_toggle = 1'b1;
        wait (display_commit_toggle == 1'b1);
        display_commit_ack_toggle = 1'b1;
        wait (!dut.display_commit_pending);

        // Selecting image one at 150 percent updates only its table entry.
        @(negedge clk);
        zoom_image_idx = 4'd1;
        zoom_level = 3'd4;
        zoom_request = 1'b1;
        @(negedge clk);
        zoom_request = 1'b0;
        wait (load_count == 6);
        if (dut.load_idx != 2'd1 || dut.load_zoom_level != 3'd4)
            $fatal(11, "image one zoom selection was not loaded");
        wait (dut.source_done_seen);
        @(negedge clk);
        write_finish_toggle = 1'b0;
        wait (display_commit_toggle == 1'b0);
        display_commit_ack_toggle = 1'b0;
        wait (!dut.display_commit_pending);

        // Returning home must restore image zero's earlier 50-percent value.
        @(negedge clk);
        home_request = 1'b1;
        @(negedge clk);
        home_request = 1'b0;
        wait (load_count == 7);
        if (dut.load_idx != 2'd0 || dut.load_zoom_level != 3'd0)
            $fatal(12, "home did not restore image zero's independent zoom");

        wait (dut.source_done_seen);
        @(negedge clk);
        write_finish_toggle = 1'b1;
        wait (display_commit_toggle == 1'b1);
        display_commit_ack_toggle = 1'b1;
        wait (!dut.display_commit_pending);

        // Leaving SETTINGS may flush the final zoom value in the same window
        // as HOME. Store that image's setting, but HOME must suppress the
        // preview reload so the screen cannot jump away from image zero.
        @(negedge clk);
        zoom_image_idx = 4'd1;
        zoom_level = 3'd1;
        zoom_request = 1'b1;
        home_request = 1'b1;
        @(negedge clk);
        zoom_request = 1'b0;
        home_request = 1'b0;
        repeat (12) @(posedge clk);
        if (load_count != 7 || dut.zoom_req_pending || dut.home_req_pending ||
            dut.image_zoom1 != 3'd1)
            $fatal(14, "home did not suppress delayed preview while storing zoom");

        // If a file changes or becomes corrupt after startup scanning, reject
        // it before commit, leave the current frame visible, and exit busy so
        // a later request can retry or select another image.
        key_next = 1'b0;
        repeat (25) @(posedge clk);
        key_next = 1'b1;
        wait (load_count == 8);
        @(negedge clk);
        dut.bmp_read_m0.load_error_pulse = 1'b1;
        @(negedge clk);
        dut.bmp_read_m0.load_error_pulse = 1'b0;
        repeat (3) @(posedge clk);
        if (dut.load_busy || display_image_idx != 4'd0 ||
            disp_buf_idx != 2'd0 || display_commit_toggle != 1'b1)
            $fatal(15, "rejected BMP did not preserve the displayed frame");

        // The application can select the twelfth page directly. This proves
        // the widened index, sector table, and exact-page request path rather
        // than only relying on seven relative NEXT operations.
        @(negedge clk);
        image_request_idx = 4'd11;
        image_request_prev = 1'b1;
        image_request = 1'b1;
        @(negedge clk);
        image_request = 1'b0;
        wait (load_count == 9);
        if (dut.load_idx != 4'd11 || dut.load_sector != 32'h80b0_0000 ||
            dut.load_zoom_level != 3'd2 || !dut.load_page_right)
            $fatal(16, "exact request did not load image eleven");
        wait (dut.source_done_seen);
        @(negedge clk);
        write_finish_toggle = 1'b0;
        wait (display_commit_toggle == 1'b0);
        if (display_image_idx != 4'd11 || disp_buf_idx != 2'd1 ||
            !display_page_right)
            $fatal(17, "twelfth page did not commit atomically");
        display_commit_ack_toggle = 1'b0;
        wait (!dut.display_commit_pending);

        // A standalone SD recovery must preserve the complete video frame.
        // In particular, clearing a high commit toggle would look like a new
        // request to the video domain even though no frame was written.
        @(negedge clk);
        dut.display_commit_toggle = 1'b1;
        display_commit_ack_toggle = 1'b1;
        dut.sd_card_top_m0.sd_init_done = 1'b0;
        repeat (4) @(negedge clk);
        if (display_commit_toggle !== 1'b1 || !display_valid ||
            disp_buf_idx != 2'd1 || display_image_idx != 4'd11 ||
            !dut.first_image_committed)
            $fatal(21, "SD recovery discarded the last committed video frame");
        home_request = 1'b1;
        @(negedge clk);
        home_request = 1'b0;
        if (!dut.home_req_pending)
            $fatal(24, "HOME was lost during SD recovery");
        dut.sd_card_top_m0.sd_init_done = 1'b1;
        dut.bmp_read_m0.ready = 1'b1;
        wait (dut.scan_start_pulse);
        @(negedge clk);
        if (display_commit_toggle !== 1'b1 || !display_valid ||
            display_image_idx != 4'd11 || !dut.first_image_committed ||
            !dut.home_req_pending)
            $fatal(22, "SD rescan fabricated a video commit or first-image reload");
        dut.u_fat32_volume_scanner.state = 5'd0;
        dut.bmp_read_m0.ready = 1'b0;
        report_found(4'd0);
        report_found(4'd1);
        finish_scan();
        dut.bmp_read_m0.ready = 1'b1;
        wait (load_count == 10);
        if (dut.load_idx != 4'd0 || !dut.load_busy)
            $fatal(25, "queued HOME did not reload image zero after SD rescan");

        // A bad first image must stay blocked across the SD-stack recovery
        // cycle.  Otherwise sd_init_done dropping would clear the guard and
        // create an endless scan/load/recover loop on the same corrupt file.
        @(negedge clk);
        rst = 1'b1;
        dut.sd_card_top_m0.sd_init_done = 1'b0;
        dut.scan_done = 1'b0;
        dut.bmp_read_m0.ready = 1'b0;
        load_count = 0;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        dut.sd_card_top_m0.sd_init_done = 1'b1;
        dut.bmp_read_m0.ready = 1'b1;
        wait (dut.scan_start_pulse);
        dut.u_fat32_volume_scanner.state = 5'd0;
        dut.bmp_read_m0.ready = 1'b0;
        report_found(4'd0);
        finish_scan();
        dut.bmp_read_m0.ready = 1'b1;
        wait (load_count == 1);
        @(negedge clk);
        dut.bmp_read_m0.load_error_pulse = 1'b1;
        @(negedge clk);
        dut.bmp_read_m0.load_error_pulse = 1'b0;
        dut.sd_card_top_m0.sd_init_done = 1'b0;
        dut.scan_done = 1'b0;
        repeat (3) @(negedge clk);
        dut.sd_card_top_m0.sd_init_done = 1'b1;
        dut.bmp_read_m0.ready = 1'b1;
        wait (dut.scan_start_pulse);
        dut.u_fat32_volume_scanner.state = 5'd0;
        dut.bmp_read_m0.ready = 1'b0;
        report_found(4'd0);
        finish_scan();
        dut.bmp_read_m0.ready = 1'b1;
        repeat (20) @(posedge clk);
        if (load_count != 1 || !dut.first_image_load_failed)
            $fatal(19, "first-image failure guard did not survive SD recovery");

        // Directory metadata emitted before a failed sector is not usable.
        @(negedge clk);
        dut.first_image_load_failed = 1'b0;
        dut.scan_done = 1'b0;
        dut.u_fat32_volume_scanner.error_code = 8'h10;
        finish_scan();
        repeat (20) @(negedge clk);
        if (load_count != 1 || dut.scan_done || content_ready || dut.state_code != 4'hE)
            $fatal(1, "failed directory scan exposed partial metadata");

        @(negedge clk);
        force dut.bmp_sd_recover_pulse = 1'b1;
        force dut.voice_sd_recover_pulse = 1'b1;
        force dut.fs_scan_sd_recover_pulse = 1'b1;
        force dut.bridge_sd_recover_pulse = 1'b1;
        force dut.virtual_sd_sec_read_error = 1'b1;
        @(negedge clk);
        if (debug_event_toggle[12:8] != 5'b11111)
            $fatal(23, "SD fault-source diagnostics missed a pulse");
        release dut.bmp_sd_recover_pulse;
        release dut.voice_sd_recover_pulse;
        release dut.fs_scan_sd_recover_pulse;
        release dut.bridge_sd_recover_pulse;
        release dut.virtual_sd_sec_read_error;

        // A disabled reader can keep stop high for many cycles. The audio
        // notification must toggle once, including when the reader finished
        // but an old clip is still buffered in the audio FIFO.
        @(negedge clk); narration_enable = 1;
        repeat (3) @(negedge clk);
        saved_voice_stop = dut.voice_stop_toggle;
        narration_enable = 0;
        repeat (12) @(negedge clk);
        if (dut.voice_stop_toggle === saved_voice_stop)
            $fatal(1,"narration disable did not notify idle-reader audio");
        saved_voice_stop = dut.voice_stop_toggle;
        repeat (11) @(negedge clk);
        if (dut.voice_stop_toggle !== saved_voice_stop)
            $fatal(1,"disabled narration repeatedly toggled stop");
        home_request = 1;
        @(negedge clk); home_request = 0;
        if (dut.voice_stop_toggle !== saved_voice_stop)
            $fatal(1,"closely spaced cancellation causes cancelled the CDC token");
        saved_voice_stop = dut.voice_stop_toggle;
        repeat (10) @(negedge clk);
        if (dut.voice_stop_toggle !== saved_voice_stop)
            $fatal(1,"HOME repeated stop without a new navigation event");
        // A newly validated clip re-arms exactly one future cancellation.
        narration_enable = 1;
        force dut.home_req_pending = 0;
        force dut.voice_stop_pulse = 0;
        force dut.voice_reader_start_pulse = 1;
        @(negedge clk); release dut.voice_reader_start_pulse;
        repeat (3) @(negedge clk);
        home_request = 1;
        @(negedge clk); home_request = 0;
        if (dut.voice_stop_toggle === saved_voice_stop)
            $fatal(1,"new clip failed to re-arm stop notification");
        release dut.home_req_pending;
        release dut.voice_stop_pulse;
        $display("TEST_PASS tb_sd_card_bmp_control");
        $finish;
    end

    initial begin
        #500000;
        $fatal(13, "test timeout");
    end
endmodule

module bmp_read #(parameter integer CROP_READ_ENABLE=0) (
    input clk,
    input rst,
    output reg ready,
    input scan_start,
    input [31:0] scan_start_sector,
    input [31:0] scan_max_sector,
    input [3:0] scan_target_count,
    output reg scan_done,
    output reg scan_found_valid,
    output reg [31:0] scan_found_sector,
    output reg [3:0] scan_found_total,
    output reg scan_found_voice,
    output reg [31:0] scan_found_voice_offset,
    input load_start,
    input [31:0] load_sector,
    output reg load_error_pulse,
    output reg sd_recover_pulse,
    input sd_init_done,
    output reg [3:0] state_code,
    input [15:0] bmp_width,
    input [15:0] bmp_height,
    output reg [15:0] source_width,
    output reg [15:0] source_height,
    output reg write_req,
    input write_req_ack,
    input source_start,
    input [15:0] source_first_row,
    input [15:0] source_roi_rows,
    output reg sd_sec_read,
    output reg [31:0] sd_sec_read_addr,
    input [7:0] sd_sec_read_data,
    input sd_sec_read_data_valid,
    input sd_sec_read_end,
    input sd_sec_read_error,
    output reg bmp_data_wr_en,
    output reg [23:0] bmp_data
);
    initial begin
        ready = 1'b0;
        scan_done = 1'b0;
        scan_found_valid = 1'b0;
        scan_found_sector = 32'd0;
        scan_found_total = 4'd0;
        scan_found_voice = 1'b0;
        scan_found_voice_offset = 32'd0;
        load_error_pulse = 1'b0;
        sd_recover_pulse = 1'b0;
        state_code = 4'd0;
        write_req = 1'b0;
        sd_sec_read = 1'b0;
        sd_sec_read_addr = 32'd0;
        bmp_data_wr_en = 1'b0;
        bmp_data = 24'd0;
        source_width = 16'd640;
        source_height = 16'd480;
    end
endmodule

module lesson_voice_reader (
    input clk,
    input rst,
    input start,
    input stop,
    input [31:0] bmp_sector,
    input [31:0] voice_byte_offset,
    input [1:0] expected_page,
    input buffer_ready,
    input [1:0] speed_level,
    input speed_toggle,
    output ready,
    output busy,
    output voice_start_pulse,
    output voice_end_pulse,
    output voice_error_pulse,
    output sd_recover_pulse,
    output [1:0] voice_page,
    output [31:0] voice_sample_total,
    output voice_data_valid,
    output [7:0] voice_data,
    output [1:0] voice_data_speed,
    output sd_sec_read,
    output [31:0] sd_sec_read_addr,
    input [7:0] sd_sec_read_data,
    input sd_sec_read_data_valid,
    input sd_sec_read_end,
    input sd_sec_read_error
);
    assign ready = 1'b1;
    assign busy = 1'b0;
    assign voice_start_pulse = 1'b0;
    assign voice_end_pulse = 1'b0;
    assign voice_error_pulse = 1'b0;
    assign sd_recover_pulse = 1'b0;
    assign voice_page = 2'd0;
    assign voice_sample_total = 32'd0;
    assign voice_data_valid = 1'b0;
    assign voice_data = 8'd0;
    assign voice_data_speed = 2'd3;
    assign sd_sec_read = 1'b0;
    assign sd_sec_read_addr = 32'd0;
endmodule

module sd_card_top (
    input clk,
    input rst,
    input recover,
    output SD_nCS,
    output SD_DCLK,
    output SD_MOSI,
    input SD_MISO,
    output reg sd_init_done,
    input sd_sec_read,
    input [31:0] sd_sec_read_addr,
    output [7:0] sd_sec_read_data,
    output sd_sec_read_data_valid,
    output reg sd_sec_read_end,
    input sd_sec_write,
    input [31:0] sd_sec_write_addr,
    input [7:0] sd_sec_write_data,
    output sd_sec_write_data_req,
    output sd_sec_write_end
);
    assign SD_nCS = 1'b1;
    assign SD_DCLK = 1'b0;
    assign SD_MOSI = 1'b0;
    assign sd_sec_read_data = 8'd0;
    assign sd_sec_read_data_valid = 1'b0;
    assign sd_sec_write_data_req = 1'b0;
    assign sd_sec_write_end = 1'b0;

    initial begin
        sd_init_done = 1'b0;
        sd_sec_read_end = 1'b0;
    end
endmodule
