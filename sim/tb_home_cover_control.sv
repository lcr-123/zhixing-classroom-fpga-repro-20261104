`timescale 1ns/1ps

module tb_home_cover_control;
    tb_sd_card_bmp_control #(.HOME_TEST(1)) fixture();
    integer index;
    integer expected_loads;

    task automatic scan_cards;
        input with_home;
        begin
            wait (fixture.dut.scan_start_pulse);
            fixture.dut.u_fat32_volume_scanner.state = 0;
            fixture.dut.bmp_read_m0.ready = 0;
            // Cover arrives last, after all twelve ordinary entries.
            for (index = 0; index < 12; index = index + 1)
                fixture.report_found(index);
            if (with_home) fixture.report_found(12);
            fixture.finish_scan();
            fixture.dut.bmp_read_m0.ready = 1;
        end
    endtask

    task automatic reset_loader;
        begin
            @(negedge fixture.clk);
            fixture.rst = 1;
            fixture.dut.sd_card_top_m0.sd_init_done = 0;
            fixture.dut.bmp_read_m0.ready = 0;
            fixture.write_finish_toggle = 0;
            fixture.display_commit_ack_toggle = 0;
            repeat (4) @(negedge fixture.clk);
            fixture.load_count = 0;
            fixture.rst = 0;
            fixture.dut.sd_card_top_m0.sd_init_done = 1;
            fixture.dut.bmp_read_m0.ready = 1;
        end
    endtask

    task automatic commit_frame;
        input [3:0] expected_index;
        reg old_commit;
        begin
            wait (fixture.dut.source_done_seen);
            repeat (4) @(negedge fixture.clk);
            if (fixture.display_valid && fixture.display_image_idx == expected_index)
                $fatal(1, "new frame became visible before writer completion");
            old_commit = fixture.display_commit_toggle;
            fixture.write_finish_toggle = ~fixture.write_finish_toggle;
            wait (fixture.display_commit_toggle != old_commit);
            #1;
            if (!fixture.display_valid || fixture.display_image_idx != expected_index)
                $fatal(1, "wrong committed image: %0d", fixture.display_image_idx);
            fixture.display_commit_ack_toggle = fixture.display_commit_toggle;
            wait (!fixture.dut.display_commit_pending);
        end
    endtask

    initial begin
        reset_loader();
        scan_cards(1);
        wait (fixture.load_count == 1);
        if (fixture.dut.load_idx != 12 || fixture.dut.load_sector != 32'h80c00000 ||
            fixture.dut.img_found_count != 12 || !fixture.content_ready ||
            fixture.dut.load_zoom_level != 2)
            $fatal(1, "cover changed course indexing/readiness or boot target");
        commit_frame(12);
        @(negedge fixture.clk);
        fixture.image_request_settings = 1;
        fixture.image_request_idx = 0;
        fixture.image_request = 1;
        @(negedge fixture.clk); fixture.image_request = 0;
        wait (fixture.load_count == 2);
        if (fixture.dut.load_idx != 0 || fixture.dut.load_sector != 32'h80000000)
            $fatal(1, "first lesson was renumbered");
        commit_frame(0);
        if (!fixture.display_settings_entry)
            $fatal(1, "SETTINGS first lesson lost its fade tag");
        fixture.image_request_settings = 0;
        @(negedge fixture.clk); fixture.home_request = 1;
        @(negedge fixture.clk); fixture.home_request = 0;
        wait (fixture.load_count == 3);
        if (fixture.dut.load_idx != 12 || fixture.write_buf_idx == fixture.disp_buf_idx)
            $fatal(1, "HOME did not load cover into the inactive buffer");
        commit_frame(12);
        @(negedge fixture.clk); fixture.home_request = 1;
        @(negedge fixture.clk); fixture.home_request = 0;
        repeat (20) @(negedge fixture.clk);
        if (fixture.load_count != 3) $fatal(1, "redundant HOME reloaded cover");

        // Invalid cover at cold boot must try the ordinary first card once.
        reset_loader();
        scan_cards(1);
        wait (fixture.load_count == 1);
        @(negedge fixture.clk); fixture.dut.bmp_read_m0.load_error_pulse = 1;
        @(negedge fixture.clk); fixture.dut.bmp_read_m0.load_error_pulse = 0;
        wait (fixture.load_count == 2);
        if (fixture.dut.load_idx != 0 || !fixture.dut.home_image_failed ||
            fixture.dut.first_image_load_failed)
            $fatal(1, "bad cover did not fall back to lesson zero");
        commit_frame(0);
        repeat (20) @(negedge fixture.clk);
        if (fixture.load_count != 2) $fatal(1, "bad cover retried forever");

        // Same error during a return preserves the displayed course image.
        reset_loader();
        scan_cards(1);
        wait (fixture.load_count == 1);
        commit_frame(12);
        @(negedge fixture.clk); fixture.image_request_idx = 2; fixture.image_request = 1;
        @(negedge fixture.clk); fixture.image_request = 0;
        wait (fixture.load_count == 2);
        commit_frame(2);
        @(negedge fixture.clk); fixture.home_request = 1;
        @(negedge fixture.clk); fixture.home_request = 0;
        wait (fixture.load_count == 3);
        @(negedge fixture.clk); fixture.dut.bmp_read_m0.load_error_pulse = 1;
        @(negedge fixture.clk); fixture.dut.bmp_read_m0.load_error_pulse = 0;
        wait (fixture.load_count == 4);
        if (fixture.display_image_idx != 2 || fixture.dut.load_idx != 0)
            $fatal(1, "bad return cover discarded previous complete frame");
        commit_frame(0);

        // Old twelve-file TF cards retain the previous startup behavior.
        reset_loader();
        scan_cards(0);
        wait (fixture.load_count == 1);
        if (fixture.dut.load_idx != 0 || !fixture.content_ready)
            $fatal(1, "old TF card no longer boots");
        commit_frame(0);
        $display("TEST_PASS tb_home_cover_control: boot, lesson, HOME, ACK, bad/missing cover");
        $finish;
    end
endmodule
