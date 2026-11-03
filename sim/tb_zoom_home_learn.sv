`timescale 1ns/1ps

module tb_zoom_home_learn;
    tb_sd_card_bmp_control #(.HOME_TEST(1)) fixture();
    integer index;

    task automatic commit_frame(input [3:0] slot, input [2:0] zoom);
        reg previous_commit;
        begin
            wait (fixture.dut.source_done_seen);
            previous_commit = fixture.display_commit_toggle;
            @(negedge fixture.clk);
            fixture.write_finish_toggle = ~fixture.write_finish_toggle;
            wait (fixture.display_commit_toggle != previous_commit);
            #1;
            if (fixture.display_image_idx != slot ||
                fixture.display_zoom_level != zoom)
                $fatal(1, "committed slot/zoom=%0d/%0d expected=%0d/%0d",
                       fixture.display_image_idx, fixture.display_zoom_level,
                       slot, zoom);
            fixture.display_commit_ack_toggle = fixture.display_commit_toggle;
            wait (!fixture.dut.display_commit_pending);
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

        wait (fixture.load_count == 1);
        commit_frame(12, 2);
        @(negedge fixture.clk);
        fixture.image_request_settings = 1;
        fixture.image_request_idx = 0;
        fixture.image_request = 1;
        @(negedge fixture.clk); fixture.image_request = 0;
        wait (fixture.load_count == 2);
        commit_frame(0, 2);

        @(negedge fixture.clk);
        fixture.zoom_image_idx = 0;
        fixture.zoom_level = 4;
        fixture.zoom_request = 1;
        @(negedge fixture.clk); fixture.zoom_request = 0;
        wait (fixture.load_count == 3);
        if (fixture.dut.image_zoom0 != 4)
            $fatal(1, "settings zoom was not retained");

        @(negedge fixture.clk); fixture.home_request = 1;
        @(negedge fixture.clk); fixture.home_request = 0;
        // A short KEY4 can enter LEARN while the zoom frame still occupies
        // the writer and HOME is queued behind it.
        @(negedge fixture.clk);
        fixture.image_request_settings = 0;
        fixture.image_request_idx = 0;
        fixture.image_request_zoom = 4;
        fixture.image_request = 1;
        @(negedge fixture.clk); fixture.image_request = 0;
        commit_frame(0, 4);
        wait (fixture.load_count == 4);
        if (fixture.dut.load_idx != 12)
            $fatal(1, "HOME did not start loading cover");
        commit_frame(12, 2);
        repeat (20) @(negedge fixture.clk);
        if (fixture.load_count != 5 || fixture.dut.load_idx != 0 ||
            fixture.dut.load_zoom_level != 4)
            $fatal(1, "LEARN request or retained zoom lost after HOME");
        commit_frame(0, 4);

        // Waiting for HOME to finish before selecting LEARN uses the same
        // saved setting and does not depend on the queued-request path.
        @(negedge fixture.clk); fixture.home_request = 1;
        @(negedge fixture.clk); fixture.home_request = 0;
        wait (fixture.load_count == 6);
        commit_frame(12, 2);
        @(negedge fixture.clk); fixture.image_request = 1;
        @(negedge fixture.clk); fixture.image_request = 0;
        wait (fixture.load_count == 7);
        if (fixture.dut.load_idx != 0 || fixture.dut.load_zoom_level != 4)
            $fatal(1, "settled HOME lost the saved zoom");
        commit_frame(0, 4);

        // A newer HOME request cancels an older course request.
        @(negedge fixture.clk); fixture.image_request_idx = 1;
        fixture.image_request_zoom = 2;
        fixture.image_request = 1;
        @(negedge fixture.clk); fixture.image_request = 0;
        wait (fixture.load_count == 8);
        @(negedge fixture.clk); fixture.home_request = 1;
        @(negedge fixture.clk); fixture.home_request = 0;
        commit_frame(1, 2);
        wait (fixture.load_count == 9);
        commit_frame(12, 2);
        repeat (20) @(negedge fixture.clk);
        if (fixture.load_count != 9 || fixture.dut.image_req_pending)
            $fatal(1, "older course request survived HOME");
        $display("TEST_PASS tb_zoom_home_learn");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "zoom HOME LEARN timeout");
    end
endmodule
