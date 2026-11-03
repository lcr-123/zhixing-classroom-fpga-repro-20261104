`timescale 1ns/1ps

module tb_frame_buffer_commit;
    reg pixel_clk = 1'b0;
    reg pixel_rst = 1'b1;
    reg frame_boundary = 1'b0;
    reg [1:0] source_buf_idx = 2'd0;
    reg [3:0] source_image_idx = 4'd0;
    reg source_page_right = 1'b0;
    reg source_settings_entry = 1'b0;
    reg [2:0] source_zoom_level = 3'd2;
    reg source_display_valid = 1'b0;
    reg source_commit_toggle = 1'b0;
    wire commit_ack_toggle;
    wire [1:0] display_buf_idx;
    wire [1:0] transition_buf_idx;
    wire [3:0] display_image_idx;
    wire [2:0] display_zoom_level;
    wire display_valid;
    wire lesson_image_ready;
    wire transition_active;
    wire [4:0] transition_alpha;
    wire [1:0] transition_effect;

    always #20 pixel_clk = ~pixel_clk;

    frame_buffer_commit dut (
        .pixel_clk(pixel_clk),
        .pixel_rst(pixel_rst),
        .frame_boundary(frame_boundary),
        .source_buf_idx(source_buf_idx),
        .source_image_idx(source_image_idx),
        .source_page_right(source_page_right),
        .source_settings_entry(source_settings_entry),
        .source_zoom_level(source_zoom_level),
        .source_display_valid(source_display_valid),
        .source_commit_toggle(source_commit_toggle),
        .commit_ack_toggle(commit_ack_toggle),
        .display_buf_idx(display_buf_idx),
        .transition_buf_idx(transition_buf_idx),
        .display_image_idx(display_image_idx),
        .display_zoom_level(display_zoom_level),
        .display_valid(display_valid),
        .lesson_image_ready(lesson_image_ready),
        .transition_active(transition_active),
        .transition_alpha(transition_alpha),
        .transition_effect(transition_effect)
    );

    task automatic pulse_boundary;
        begin
            @(negedge pixel_clk);
            frame_boundary = 1'b1;
            @(negedge pixel_clk);
            frame_boundary = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge pixel_clk);
        pixel_rst = 1'b0;

        @(negedge pixel_clk);
        source_buf_idx = 2'd1;
        source_image_idx = 4'd0;
        source_zoom_level = 3'd0;
        source_display_valid = 1'b1;
        source_commit_toggle = 1'b1;
        repeat (6) @(posedge pixel_clk);
        #1;
        if (display_buf_idx != 2'd0 || display_valid || commit_ack_toggle)
            $fatal(1, "buffer changed before frame boundary");

        pulse_boundary();
        #1;
        if (display_buf_idx != 2'd1 || display_image_idx != 4'd0 ||
            display_zoom_level != 3'd0 ||
            !display_valid ||
            commit_ack_toggle != 1'b1)
            $fatal(2, "first frame commit failed");

        @(negedge pixel_clk);
        source_buf_idx = 2'd0;
        source_image_idx = 4'd1;
        source_zoom_level = 3'd4;
        source_commit_toggle = 1'b0;
        repeat (6) @(posedge pixel_clk);
        #1;
        if (display_buf_idx != 2'd1 || commit_ack_toggle != 1'b1)
            $fatal(3, "second buffer changed before frame boundary");

        pulse_boundary();
        #1;
        if (!transition_active || transition_buf_idx != 2'd0 ||
            transition_alpha != 5'd1 || display_zoom_level != 3'd0 ||
            transition_effect != 2'd2 || commit_ack_toggle != 1'b1)
            $fatal(4, "page 01-to-02 left turn did not start at frame boundary");

        repeat (14) pulse_boundary();
        #1;
        if (!transition_active || transition_alpha != 5'd15)
            $fatal(5, "transition alpha progression failed");

        pulse_boundary();
        #1;
        if (transition_active || display_buf_idx != 2'd0 ||
            display_image_idx != 4'd1 || display_zoom_level != 3'd4 ||
            commit_ack_toggle != 1'b0)
            $fatal(6, "transition did not commit target frame");

        // The second learning handoff, page 02 to page 03, selects the
        // deterministic shatter effect and keeps it stable through commit.
        @(negedge pixel_clk);
        source_buf_idx = 2'd1;
        source_image_idx = 4'd2;
        source_zoom_level = 3'd2;
        source_commit_toggle = 1'b1;
        repeat (6) @(posedge pixel_clk);
        pulse_boundary();
        #1;
        if (!transition_active || transition_effect != 2'd1 ||
            transition_alpha != 5'd1 || display_image_idx != 4'd1)
            $fatal(7, "page 02-to-03 shatter was not selected");

        repeat (14) pulse_boundary();
        #1;
        if (!transition_active || transition_effect != 2'd1 ||
            transition_alpha != 5'd15)
            $fatal(8, "shatter effect was not stable across the transition");

        pulse_boundary();
        #1;
        if (transition_active || transition_effect != 2'd0 ||
            display_image_idx != 4'd2 || commit_ack_toggle != 1'b1)
            $fatal(9, "shatter transition did not commit page 03 atomically");

        // A double-click on page 03 returns directly to page 02.
        @(negedge pixel_clk);
        source_buf_idx = 2'd0;
        source_image_idx = 4'd1;
        source_page_right = 1'b1;
        source_commit_toggle = 1'b0;
        repeat (6) @(posedge pixel_clk);
        pulse_boundary();
        #1;
        if (!transition_active || transition_effect != 2'd3 ||
            transition_alpha != 5'd1 || display_image_idx != 4'd2 ||
            commit_ack_toggle != 1'b1)
            $fatal(12, "page 03-to-02 right turn did not start atomically");
        repeat (14) pulse_boundary();
        #1;
        if (!transition_active || transition_effect != 2'd3 ||
            transition_alpha != 5'd15)
            $fatal(13, "page 03-to-02 right turn changed during transition");
        pulse_boundary();
        #1;
        if (transition_active || display_image_idx != 4'd1 ||
            commit_ack_toggle != 1'b0)
            $fatal(14, "page 03-to-02 did not commit page 02");

        @(negedge pixel_clk);
        source_buf_idx = 2'd1;
        source_image_idx = 4'd0;
        source_commit_toggle = 1'b1;
        repeat (6) @(posedge pixel_clk);
        pulse_boundary();
        #1;
        if (!transition_active || transition_effect != 2'd0 ||
            display_image_idx != 4'd1)
            $fatal(15, "page 02-to-01 did not retain fade");
        repeat (15) pulse_boundary();
        #1;
        if (transition_active || display_image_idx != 4'd0 ||
            commit_ack_toggle != 1'b1)
            $fatal(16, "page 02-to-01 did not commit page 01");

        @(negedge pixel_clk);
        source_buf_idx = 2'd0;
        source_image_idx = 4'd1;
        source_page_right = 1'b0;
        source_commit_toggle = 1'b0;
        repeat (6) @(posedge pixel_clk);
        pulse_boundary();
        #1;
        if (!transition_active || transition_effect != 2'd2 ||
            display_image_idx != 4'd0)
            $fatal(17, "page 01-to-02 did not turn left after backward navigation");
        repeat (15) pulse_boundary();

        // Entering the practice card selects the right-to-left page turn.
        @(negedge pixel_clk);
        source_buf_idx = 2'd1;
        source_image_idx = 4'd3;
        source_commit_toggle = 1'b1;
        repeat (6) @(posedge pixel_clk);
        pulse_boundary();
        #1;
        if (!transition_active || transition_effect != 2'd2)
            $fatal(10, "practice transition did not select left page turn");

        repeat (15) pulse_boundary();
        @(negedge pixel_clk);
        source_buf_idx = 2'd0;
        source_image_idx = 4'd7;
        source_page_right = 1'b1;
        source_commit_toggle = 1'b0;
        repeat (6) @(posedge pixel_clk);
        pulse_boundary();
        #1;
        if (!transition_active || transition_effect != 2'd3)
            $fatal(11, "previous practice page did not turn right");

        repeat (15) pulse_boundary();
        // Zoom replaces one complete version of the same page at a single
        // safe edge, avoiding a 16-frame blend of differently sized text.
        @(negedge pixel_clk);
        source_buf_idx = 2'd1;
        source_zoom_level = 3'd4;
        source_commit_toggle = 1'b1;
        repeat (6) @(posedge pixel_clk);
        #1;
        if (display_buf_idx != 0 || display_zoom_level != 2 ||
            commit_ack_toggle != 0 || transition_active)
            $fatal(18, "zoom changed before safe frame edge");
        pulse_boundary();
        #1;
        if (display_buf_idx != 1 || display_zoom_level != 4 ||
            display_image_idx != 7 || commit_ack_toggle != 1 || transition_active)
            $fatal(19, "zoom was not committed without a multi-frame blend");
        // A complete HOME cover uses slot 12. Learning turns left from it;
        // SETTINGS loads lesson zero but fades into its preview instead.
        @(negedge pixel_clk);
        source_buf_idx = 2'd0;
        source_image_idx = 4'd12;
        source_zoom_level = 3'd2;
        source_commit_toggle = 1'b0;
        repeat (6) @(negedge pixel_clk);
        pulse_boundary();
        repeat (15) pulse_boundary();
        if (display_image_idx != 4'd12 || !display_valid || lesson_image_ready)
            $fatal(20, "HOME cover did not commit");
        @(negedge pixel_clk);
        source_buf_idx = 2'd1;
        source_image_idx = 4'd0;
        source_commit_toggle = 1'b1;
        repeat (6) @(negedge pixel_clk);
        pulse_boundary();
        if (!transition_active || transition_effect != 2'd2 ||
            display_image_idx != 4'd12 || lesson_image_ready)
            $fatal(21, "HOME-to-LEARN did not turn left");
        repeat (13) pulse_boundary();
        #1;
        if (!transition_active || transition_alpha != 5'd14 ||
            lesson_image_ready)
            $fatal(22, "lesson waveform became ready before the final frame");
        pulse_boundary();
        #1;
        if (!transition_active || transition_alpha != 5'd15 ||
            !lesson_image_ready)
            $fatal(23, "lesson waveform was not armed for the final frame");
        pulse_boundary();
        #1;
        if (display_image_idx != 4'd0 || transition_active ||
            !lesson_image_ready)
            $fatal(24, "HOME-to-LEARN did not reveal image and waveform together");
        @(negedge pixel_clk);
        source_buf_idx = 2'd0;
        source_image_idx = 4'd12;
        source_commit_toggle = 1'b0;
        repeat (6) @(negedge pixel_clk);
        pulse_boundary();
        repeat (15) pulse_boundary();
        @(negedge pixel_clk);
        source_buf_idx = 2'd1;
        source_image_idx = 4'd0;
        source_settings_entry = 1'b1;
        source_commit_toggle = 1'b1;
        repeat (6) @(negedge pixel_clk);
        pulse_boundary();
        if (!transition_active || transition_effect != 2'd0 ||
            display_image_idx != 4'd12)
            $fatal(25, "HOME-to-SETTINGS did not fade from cover");
        repeat (15) pulse_boundary();
        if (display_image_idx != 4'd0 || transition_active)
            $fatal(26, "SETTINGS preview is not the first lesson");
        $display("TEST_PASS tb_frame_buffer_commit");
        $finish;
    end
endmodule
