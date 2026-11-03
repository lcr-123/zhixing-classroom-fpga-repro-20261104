`timescale 1ns/1ps

module tb_practice_no_auto_page;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg key_auto = 1'b1;
    wire auto_play_active;
    wire [12:0] debug_event_toggle;
    integer load_count = 0;

    always #5 clk = ~clk;
    always @(posedge clk)
        if (dut.load_start_pulse)
            load_count <= load_count + 1;

    sd_card_bmp #(
        .CLK_FREQ_HZ(1000),
        .SCAN_TARGET_COUNT(4'd12),
        .AUTO_PLAY_ENABLE(1'b0)
    ) dut (
        .clk(clk), .rst(rst), .key_next(1'b1), .key_auto(key_auto),
        .home_request(1'b0), .image_request(1'b0),
        .image_request_idx(4'd0), .image_request_zoom(3'd2), .zoom_request(1'b0),
        .zoom_level(3'd2), .zoom_image_idx(4'd0),
        .narration_enable(1'b0), .voice_fifo_space_available(1'b1),
        .voice_fifo_empty(1'b1), .content_ready(), .state_code(),
        .display_image_idx(), .debug_event_toggle(debug_event_toggle),
        .auto_play_active(auto_play_active),
        .display_zoom_level(), .bmp_width(16'd640),
        .bmp_height(16'd480), .display_valid(),
        .write_finish_toggle(1'b0), .write_buf_idx(), .disp_buf_idx(),
        .display_commit_toggle(), .display_commit_ack_toggle(1'b0),
        .write_req(), .write_req_ack(1'b0), .write_en(), .write_data(),
        .voice_fifo_write(), .voice_fifo_data(), .voice_start_toggle(),
        .voice_end_toggle(), .voice_stop_toggle(), .voice_clip_index(), .voice_sample_total(), .narration_busy(),
        .SD_nCS(), .SD_DCLK(), .SD_MOSI(), .SD_MISO(1'b1)
    );

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        force dut.sd_card_top_m0.sd_init_done = 1'b1;
        force dut.bmp_read_m0.ready = 1'b1;
        force dut.scan_kicked = 1'b1;
        force dut.scan_done = 1'b1;
        force dut.img_found_count = 4'd12;
        force dut.first_image_committed = 1'b1;
        force dut.display_valid = 1'b1;
        force dut.display_commit_pending = 1'b0;
        force dut.img_idx = 4'd3;

        key_auto = 1'b0;
        repeat (30) @(posedge clk);
        key_auto = 1'b1;
        repeat (5) @(posedge clk);
        #1;
        if (auto_play_active || load_count != 0)
            $fatal(1, "disabled automatic playback accepted a key press");

        // Even a stale enabled state and expired timer must not launch a
        // practice-card load when the production switch is disabled.
        force dut.auto_play_en = 1'b1;
        force dut.auto_cnt = 32'd999;
        repeat (10) @(posedge clk);
        #1;
        if (load_count != 0 || debug_event_toggle[6])
            $fatal(2, "disabled automatic playback loaded another card");

        $display("TEST_PASS tb_practice_no_auto_page");
        $finish;
    end
endmodule
