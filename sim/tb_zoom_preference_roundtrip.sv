`timescale 1ns/1ps

module tb_zoom_preference_roundtrip;
    tb_sd_card_bmp_control #(.HOME_TEST(1)) fixture();
    reg ref_clk = 0, ref_rst = 1;
    reg settings_active = 0;
    reg [1:0] selector = 0;
    reg zoom_next = 0, decrement = 0, increment = 0;
    wire [2:0] zoom_level;
    wire [1:0] zoom_index;
    wire [2:0] zoom_lookup_level;
    wire zoom_toggle;
    reg [2:0] toggle_sync = 0;
    reg [2:0] level_meta = 2, level_sync = 2;
    reg [3:0] index_meta = 0, index_sync = 0;
    integer index, completed_load = -1;

    always #10 ref_clk = ~ref_clk;

    video_control_arbiter #(
        .ZOOM_APPLY_DELAY_CYCLES(6), .ZOOM_APPLY_COUNTER_WIDTH(4)
    ) controls (
        .clk(ref_clk), .rst(ref_rst),
        .uart_brightness(3'sd0), .uart_contrast(2'd1),
        .uart_osd_enable(1'b1), .uart_subtitle_enable(1'b1),
        .uart_control_toggle(1'b0), .settings_active(settings_active),
        .select_parameter_async(selector), .zoom_next_pulse(zoom_next),
        .zoom_prev_pulse(1'b0), .decrement_pulse(decrement),
        .increment_pulse(increment), .auto_selector_async(1'b0),
        .ambient_level(3'sd0), .ambient_valid(1'b0),
        .auto_brightness_enable(), .brightness(), .contrast(),
        .osd_enable(), .subtitle_enable(), .control_toggle(),
        .zoom_level(zoom_level), .zoom_image_index(zoom_index),
        .zoom_lookup_index(fixture.image_request_idx[1:0]),
        .zoom_lookup_level(zoom_lookup_level),
        .zoom_request_toggle(zoom_toggle), .editing_parameter(),
        .eye_comfort_enable()
    );

    always @(posedge fixture.clk) begin
        toggle_sync <= {toggle_sync[1:0], zoom_toggle};
        level_meta <= zoom_level;
        level_sync <= level_meta;
        index_meta <= {2'b0, zoom_index};
        index_sync <= index_meta;
    end

    always @(negedge fixture.clk) begin
        fixture.zoom_request = toggle_sync[2] ^ toggle_sync[1];
        fixture.zoom_level = level_sync;
        fixture.zoom_image_idx = index_sync;
        if (fixture.dut.source_done_seen &&
            completed_load != fixture.load_count) begin
            fixture.write_finish_toggle = ~fixture.write_finish_toggle;
            completed_load = fixture.load_count;
        end
        fixture.display_commit_ack_toggle = fixture.display_commit_toggle;
    end

    task automatic edit_zoom(input reg up);
        begin
            @(negedge ref_clk);
            if (up) increment = 1;
            else decrement = 1;
            @(negedge ref_clk);
            increment = 0;
            decrement = 0;
        end
    endtask

    task automatic next_preview;
        begin
            @(negedge ref_clk); zoom_next = 1;
            @(negedge ref_clk); zoom_next = 0;
        end
    endtask

    task automatic request_image(input [3:0] slot);
        begin
            @(negedge fixture.clk);
            fixture.image_request_idx = slot;
            #1;
            fixture.image_request_zoom = zoom_lookup_level;
            fixture.image_request_settings = 0;
            fixture.image_request = 1;
            @(negedge fixture.clk); fixture.image_request = 0;
            repeat (100) @(negedge fixture.clk);
        end
    endtask

    initial begin
        repeat (4) @(negedge fixture.clk);
        fixture.rst = 0;
        fixture.dut.sd_card_top_m0.sd_init_done = 1;
        fixture.dut.bmp_read_m0.ready = 1;
        wait (fixture.dut.scan_start_pulse);
        fixture.dut.u_fat32_volume_scanner.state = 0;
        fixture.dut.bmp_read_m0.ready = 0;
        for (index = 0; index < 12; index = index + 1)
            fixture.report_found(index);
        fixture.report_found(12);
        fixture.finish_scan();
        fixture.dut.bmp_read_m0.ready = 1;
        repeat (100) @(negedge fixture.clk);
        ref_rst = 0;
        settings_active = 1;
        selector = 2'b10;
        repeat (10) @(negedge ref_clk);

        edit_zoom(1); edit_zoom(1);
        repeat (100) @(negedge fixture.clk);
        next_preview();
        repeat (100) @(negedge fixture.clk);
        edit_zoom(0);
        repeat (100) @(negedge fixture.clk);
        next_preview();
        repeat (100) @(negedge fixture.clk);
        edit_zoom(1);
        repeat (100) @(negedge fixture.clk);
        if (fixture.dut.image_zoom0 != 4 || fixture.dut.image_zoom1 != 1 ||
            fixture.dut.image_zoom2 != 3)
            $fatal(1, "zoom preferences did not cross into all three SD slots");

        settings_active = 0;
        @(negedge fixture.clk); fixture.home_request = 1;
        @(negedge fixture.clk); fixture.home_request = 0;
        repeat (100) @(negedge fixture.clk);
        if (fixture.display_image_idx != 12 || fixture.display_zoom_level != 2)
            $fatal(1, "HOME cover did not commit");
        // Model loss of the SD-side preview cache; page requests still carry
        // the authoritative 50 MHz preference.
        fixture.dut.image_zoom0 = 2;
        fixture.dut.image_zoom1 = 2;
        fixture.dut.image_zoom2 = 2;
        request_image(0);
        if (fixture.display_image_idx != 0 || fixture.display_zoom_level != 4)
            $fatal(1, "first learning image lost 150 percent zoom");
        request_image(1);
        if (fixture.display_image_idx != 1 || fixture.display_zoom_level != 1)
            $fatal(1, "second learning image lost 75 percent zoom");
        request_image(2);
        if (fixture.display_image_idx != 2 || fixture.display_zoom_level != 3)
            $fatal(1, "third learning image lost 125 percent zoom");
        // The exact-page command must repair a displayed page whose cached
        // zoom disagrees, even though its image index has not changed.
        fixture.image_request_zoom = 2;
        @(negedge fixture.clk); fixture.image_request = 1;
        @(negedge fixture.clk); fixture.image_request = 0;
        repeat (100) @(negedge fixture.clk);
        if (fixture.display_image_idx != 2 || fixture.display_zoom_level != 2)
            $fatal(1, "same-page zoom mismatch was incorrectly skipped");
        $display("TEST_PASS tb_zoom_preference_roundtrip");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "zoom preference roundtrip timeout");
    end
endmodule
