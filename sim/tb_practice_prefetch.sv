`timescale 1ns/1ps

module tb_practice_prefetch;
    tb_sd_card_bmp_control #(.HOME_TEST(1), .PREFETCH_TEST(1)) f();
    integer i;
    integer before_loads;
    integer entry_cycles;
    reg saved_commit;

    task automatic request_image(input [3:0] idx);
        @(negedge f.clk); f.image_request_idx = idx; f.image_request = 1;
        @(negedge f.clk); f.image_request = 0;
    endtask

    task automatic ack_display;
        @(negedge f.clk);
        f.display_commit_ack_toggle = f.display_commit_toggle;
        wait (!f.dut.display_commit_pending);
    endtask

    task automatic finish_write;
        wait (f.dut.source_done_seen);
        @(negedge f.clk); f.write_finish_toggle = ~f.write_finish_toggle;
        wait (!f.dut.load_busy);
        #1;
    endtask

    task automatic request_home;
        @(negedge f.clk); f.home_request = 1;
        @(negedge f.clk); f.home_request = 0;
        wait (f.dut.load_busy);
        finish_write(); ack_display();
    endtask

    task automatic boot;
        @(negedge f.clk);
        f.rst = 1; f.prefetch_enable = 0; f.narration_enable = 0;
        f.image_request = 0; f.home_request = 0;
        f.write_finish_toggle = 0; f.display_commit_ack_toggle = 0;
        repeat (4) @(negedge f.clk);
        f.rst = 0;
        f.dut.sd_card_top_m0.sd_init_done = 1;
        f.dut.bmp_read_m0.ready = 1;
        wait (f.dut.scan_start_pulse);
        f.dut.u_fat32_volume_scanner.state = 0;
        f.dut.bmp_read_m0.ready = 0;
        for (i = 0; i < 13; i = i + 1) f.report_found(i);
        f.finish_scan();
        f.dut.bmp_read_m0.ready = 1;
        wait (f.dut.load_busy);
        finish_write(); ack_display();
        if (f.display_image_idx != 12) $fatal(1, "boot cover missing");
    endtask

    task automatic start_prefetch(input [3:0] idx);
        @(negedge f.clk); f.prefetch_image_idx = idx; f.prefetch_enable = 1;
        wait (f.dut.load_is_prefetch);
        #1;
        if ((idx == 0 && (f.write_buf_idx == f.disp_buf_idx ||
                          f.write_buf_idx == 2)) ||
            (idx != 0 && f.write_buf_idx != 2) || f.dut.load_idx != idx)
            $fatal(1, "prefetch did not use reserved buffer/target");
    endtask

    initial begin
        boot();
        saved_commit = f.display_commit_toggle;
        start_prefetch(0);
        finish_write();
        if (!f.dut.entry_cache_valid || f.dut.entry_cache_buf_idx != 1 ||
            f.display_image_idx != 12 || f.display_commit_toggle != saved_commit ||
            f.dut.first_lesson_frame_ready)
            $fatal(1, "HOME cache changed video or enabled quiz prefetch early");

        // The quiz read starts in HOME only after entry zero is protected.
        start_prefetch(4);
        repeat (20) @(negedge f.clk);
        if (f.dut.prefetch_valid || f.display_image_idx != 12 ||
            f.display_commit_toggle != saved_commit)
            $fatal(1, "partial quiz frame reached HOME");
        before_loads = f.load_count;
        saved_commit = f.display_commit_toggle;
        @(negedge f.clk); f.image_request_settings = 1;
        f.narration_enable = 1;
        request_image(0);
        entry_cycles = 0;
        while (f.display_commit_toggle == saved_commit) begin
            @(negedge f.clk); entry_cycles = entry_cycles + 1;
            if (entry_cycles > 5) $fatal(1, "warm settings entry did not hit cache");
        end
        if (f.load_count != before_loads || !f.dut.load_busy ||
            f.disp_buf_idx != f.dut.entry_cache_buf_idx ||
            !f.display_settings_entry)
            $fatal(1, "settings cache miss reread the BMP or lost entry metadata");
        $display("WARM_SETTINGS extra_bmp_reads=0 buffer=%0d", f.disp_buf_idx);
        ack_display();
        @(negedge f.clk); f.image_request_settings = 0;

        saved_commit = f.display_commit_toggle;
        request_image(0);
        repeat (5) @(negedge f.clk);
        if (f.display_commit_toggle == saved_commit ||
            f.display_settings_entry || !f.dut.load_busy ||
            !f.dut.first_lesson_frame_ready || f.load_count != before_loads)
            $fatal(1, "learning entry waited for quiz or kept settings metadata");
        ack_display();

        repeat (20) begin
            @(negedge f.clk);
            if (f.dut.voice_start_pulse || f.dut.voice_reader_busy)
                $fatal(1, "entry hit transferred SD ownership during BMP prefetch");
        end
        f.narration_enable = 0;
        finish_write();
        if (!f.dut.prefetch_valid || f.dut.prefetch_idx != 4 ||
            f.display_image_idx != 0)
            $fatal(1, "quiz completion disturbed entry display");
        request_home();
        before_loads = f.load_count;
        saved_commit = f.display_commit_toggle;
        request_image(0);
        entry_cycles = 0;
        while (f.display_commit_toggle == saved_commit) begin
            @(negedge f.clk); entry_cycles = entry_cycles + 1;
            if (entry_cycles > 5) $fatal(1, "warm first lesson did not hit cache");
        end
        if (f.load_count != before_loads || f.dut.load_busy ||
            f.disp_buf_idx != f.dut.entry_cache_buf_idx ||
            f.display_settings_entry ||
            !f.dut.first_lesson_frame_ready)
            $fatal(1, "first lesson cache hit did not arm quiz prefetch");
        $display("WARM_LESSON extra_bmp_reads=0 quiz_prefetch_armed=1");
        ack_display();
        saved_commit = f.display_commit_toggle;

        // Foreground lesson loads use 0/1 and preserve the normalized cache.
        request_image(1); wait (f.dut.load_busy);
        if (f.write_buf_idx == 2) $fatal(1, "lesson overwrote cache");
        finish_write(); ack_display();
        request_image(2); wait (f.dut.load_busy);
        if (f.write_buf_idx == 2) $fatal(1, "next lesson overwrote cache");
        finish_write(); ack_display();
        if (f.dut.entry_cache_valid)
            $fatal(1, "foreground overwrite retained stale entry cache");
        before_loads = f.load_count;
        saved_commit = f.display_commit_toggle;
        request_image(4);
        entry_cycles = 0;
        while (f.display_commit_toggle == saved_commit) begin
            @(negedge f.clk); entry_cycles = entry_cycles + 1;
            if (entry_cycles > 5) $fatal(1, "warm entry did not bypass read");
        end
        if (f.load_count != before_loads || f.dut.load_busy ||
            f.disp_buf_idx != 2 || f.display_image_idx != 4)
            $fatal(1, "warm entry reread or rewrote the cached image");
        $display("WARM_ENTRY cycles=%0d extra_bmp_reads=0", entry_cycles);
        ack_display();

        // A new target may not reuse buffer 2 until video acknowledges leaving
        // it (the real ACK includes the entire transition, not just capture).
        @(negedge f.clk); f.prefetch_image_idx = 5;
        repeat (15) @(negedge f.clk);
        if (f.dut.load_busy) $fatal(1, "prefetch overwrote displayed cache");
        request_image(0); wait (f.dut.load_busy); finish_write();
        before_loads = f.load_count;
        repeat (15) @(negedge f.clk);
        if (f.load_count != before_loads || f.dut.load_busy)
            $fatal(1, "prefetch overwrote transition source before ACK");
        ack_display();
        wait (f.dut.load_is_prefetch);
        repeat (2) @(negedge f.clk);
        // Enter while prefetch is in flight: one read, then reuse its result.
        before_loads = f.load_count;
        request_image(5);
        @(negedge f.clk); f.prefetch_enable = 0;
        finish_write();
        wait (f.display_image_idx == 5);
        if (f.load_count != before_loads || f.disp_buf_idx != 2)
            $fatal(1, "late entry duplicated the in-flight first-question read");
        ack_display();

        // Error is a bounded failed background attempt, preserving the page.
        request_image(0); wait (f.dut.load_busy); finish_write(); ack_display();
        start_prefetch(3);
        saved_commit = f.display_commit_toggle;
        @(negedge f.clk); f.dut.bmp_read_m0.load_error_pulse = 1;
        @(negedge f.clk); f.dut.bmp_read_m0.load_error_pulse = 0;
        before_loads = f.load_count;
        repeat (30) @(negedge f.clk);
        if (f.dut.load_busy || f.dut.prefetch_valid ||
            f.load_count != before_loads || f.display_image_idx != 0 ||
            f.display_commit_toggle != saved_commit)
            $fatal(1, "bad prefetch retried forever or changed video");
        // An explicit foreground request still retries through normal loading.
        request_image(3); wait (f.dut.load_busy);
        if (f.dut.load_is_prefetch || f.write_buf_idx == 2)
            $fatal(1, "failed prefetch prevented foreground fallback");
        finish_write(); ack_display();

        // Reset discards the completed cache and all transaction ownership.
        boot();
        if (f.dut.prefetch_valid || f.dut.load_is_prefetch || f.dut.prefetch_failed)
            $fatal(1, "reset retained a stale cache");
        // Invalid targets do not touch SD or the writer.
        before_loads = f.load_count;
        @(negedge f.clk); f.prefetch_enable = 1; f.prefetch_image_idx = 15;
        repeat (20) @(negedge f.clk);
        if (f.load_count != before_loads) $fatal(1, "out-of-range prefetch launched");

        // Voice and same-cycle foreground navigation have priority.
        force f.dut.voice_reader_busy = 1'b1;
        @(negedge f.clk); f.prefetch_image_idx = 4;
        repeat (20) @(negedge f.clk);
        if (f.load_count != before_loads) $fatal(1, "prefetch interrupted narration");
        @(negedge f.clk);
        release f.dut.voice_reader_busy;
        f.image_request_idx = 1; f.image_request = 1;
        @(negedge f.clk); f.image_request = 0;
        wait (f.dut.load_busy);
        if (f.dut.load_is_prefetch || f.dut.load_idx != 1)
            $fatal(1, "prefetch beat foreground navigation");
        $display("TEST_PASS practice first-question cache atomicity, hit, late entry, error, reset, priority");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "prefetch test watchdog");
    end
endmodule
