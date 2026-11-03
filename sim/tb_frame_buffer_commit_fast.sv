`timescale 1ns/1ps

module tb_frame_buffer_commit_fast;
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
    integer frame_index;

    always #20 pixel_clk = ~pixel_clk;

    frame_buffer_commit #(.TRANSITION_STEPS(8)) dut (
        .pixel_clk(pixel_clk), .pixel_rst(pixel_rst),
        .frame_boundary(frame_boundary), .source_buf_idx(source_buf_idx),
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
            #1;
        end
    endtask

    initial begin
        repeat (3) @(negedge pixel_clk);
        pixel_rst = 1'b0;
        source_buf_idx = 2'd1;
        source_image_idx = 4'd0;
        source_display_valid = 1'b1;
        source_commit_toggle = 1'b1;
        repeat (6) @(negedge pixel_clk);
        if (display_valid || commit_ack_toggle)
            $fatal(1, "first image appeared before a safe boundary");
        pulse_boundary();
        if (!display_valid || display_buf_idx != 2'd1 || !commit_ack_toggle)
            $fatal(2, "first complete image was not committed");

        source_buf_idx = 2'd0;
        source_image_idx = 4'd1;
        source_commit_toggle = 1'b0;
        repeat (6) @(negedge pixel_clk);
        if (transition_active || !commit_ack_toggle)
            $fatal(3, "transition started before a safe boundary");
        pulse_boundary();
        if (!transition_active || transition_alpha != 5'd2 ||
            transition_effect != 2'd2 || display_buf_idx != 2'd1 ||
            !commit_ack_toggle)
            $fatal(4, "fast left turn did not start at alpha 2");
        for (frame_index = 2; frame_index <= 7; frame_index = frame_index + 1) begin
            pulse_boundary();
            if (!transition_active || transition_alpha != frame_index * 2 ||
                display_buf_idx != 2'd1 || !commit_ack_toggle)
                $fatal(5, "old frame released during fast transition");
        end
        pulse_boundary();
        if (transition_active || display_buf_idx != 2'd0 ||
            display_image_idx != 4'd1 || commit_ack_toggle)
            $fatal(6, "target image did not commit on eighth boundary");

        source_buf_idx = 2'd1;
        source_image_idx = 4'd2;
        source_commit_toggle = 1'b1;
        repeat (6) @(negedge pixel_clk);
        pulse_boundary();
        if (!transition_active || transition_effect != 2'd1)
            $fatal(7, "shatter direction changed in fast mode");
        repeat (7) pulse_boundary();
        if (transition_active || display_image_idx != 4'd2 || !commit_ack_toggle)
            $fatal(8, "shatter transition did not finish in eight frames");

        source_buf_idx = 2'd0;
        source_image_idx = 4'd1;
        source_page_right = 1'b1;
        source_commit_toggle = 1'b0;
        repeat (6) @(negedge pixel_clk);
        pulse_boundary();
        if (!transition_active || transition_effect != 2'd3)
            $fatal(9, "reverse page direction changed in fast mode");
        repeat (7) pulse_boundary();
        if (transition_active || display_image_idx != 4'd1 || commit_ack_toggle)
            $fatal(10, "reverse page did not finish in eight frames");

        source_buf_idx = 2'd1;
        source_image_idx = 4'd12;
        source_page_right = 1'b0;
        source_commit_toggle = 1'b1;
        repeat (6) @(negedge pixel_clk);
        pulse_boundary();
        if (!transition_active || lesson_image_ready)
            $fatal(11, "lesson waveform remained visible while leaving LEARN");
        repeat (7) pulse_boundary();
        if (transition_active || display_image_idx != 4'd12 ||
            lesson_image_ready || !commit_ack_toggle)
            $fatal(12, "HOME did not commit with the lesson waveform hidden");

        source_buf_idx = 2'd0;
        source_image_idx = 4'd0;
        source_commit_toggle = 1'b0;
        repeat (6) @(negedge pixel_clk);
        pulse_boundary();
        if (!transition_active || transition_alpha != 5'd2 ||
            transition_effect != 2'd2 || lesson_image_ready)
            $fatal(13, "HOME-to-LEARN showed the waveform over the cover");
        for (frame_index = 2; frame_index <= 7; frame_index = frame_index + 1) begin
            pulse_boundary();
            if (!transition_active || transition_alpha != frame_index * 2)
                $fatal(14, "HOME-to-LEARN fast transition timing changed");
            if (lesson_image_ready != (frame_index == 7))
                $fatal(15, "lesson waveform readiness was not aligned to final frame");
        end
        pulse_boundary();
        if (transition_active || display_image_idx != 4'd0 ||
            !lesson_image_ready || commit_ack_toggle)
            $fatal(16, "lesson image and waveform readiness did not commit together");

        $display("TEST_PASS tb_frame_buffer_commit_fast");
        $finish;
    end
endmodule
