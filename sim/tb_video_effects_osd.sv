`timescale 1ns/1ps

module tb_video_effects_osd;
    reg pixel_clk = 1'b0;
    reg pixel_rst = 1'b1;
    reg frame_boundary = 1'b0;
    reg in_hs = 1'b0;
    reg in_vs = 1'b0;
    reg in_de = 1'b0;
    reg [23:0] in_rgb = 24'h000000;
    reg signed [2:0] source_brightness = 3'sd0;
    reg [1:0] source_contrast = 2'd1;
    reg source_osd_enable = 1'b1;
    reg source_subtitle_enable = 1'b1;
    reg source_control_toggle = 1'b0;
    reg [2:0] source_zoom_preview_level = 3'd2;
    reg [3:0] source_state_code = 4'd0;
    reg source_state_toggle = 1'b0;
    reg source_lesson_subtitle_active = 1'b0;
    reg [1:0] source_lesson_subtitle_clip = 2'd0;
    reg [4:0] source_lesson_subtitle_cue = 5'd0;
    reg source_lesson_subtitle_toggle = 1'b0;
    wire out_hs;
    wire out_vs;
    wire out_de;
    wire [23:0] out_rgb;
    integer output_pixels = 0;
    integer count_before;
    integer x;
    integer y;
    integer state_check;
    integer first_cell;
    integer last_cell;

    always #5 pixel_clk = ~pixel_clk;

    always @(negedge pixel_clk) begin
        if (out_de)
            output_pixels = output_pixels + 1;
    end

    task automatic end_line;
        begin
            @(negedge pixel_clk);
            in_de = 1'b0;
            @(posedge pixel_clk);
        end
    endtask

    task automatic one_pixel_line;
        input [23:0] value;
        begin
            @(negedge pixel_clk);
            in_rgb = value;
            in_de = 1'b1;
            @(posedge pixel_clk);
            end_line();
        end
    endtask

    task automatic pulse_frame_boundary;
        begin
            @(negedge pixel_clk);
            frame_boundary = 1'b1;
            @(posedge pixel_clk);
            @(negedge pixel_clk);
            frame_boundary = 1'b0;
        end
    endtask

    task automatic publish_state;
        input [3:0] value;
        begin
            @(negedge pixel_clk);
            source_state_code = value;
            source_state_toggle = ~source_state_toggle;
            repeat (6) @(posedge pixel_clk);
            #1;
        end
    endtask

    task automatic publish_lesson_subtitle;
        input active_value;
        input [1:0] clip_value;
        input [4:0] cue_value;
        begin
            @(negedge pixel_clk);
            source_lesson_subtitle_active = active_value;
            source_lesson_subtitle_clip = clip_value;
            source_lesson_subtitle_cue = cue_value;
            source_lesson_subtitle_toggle =
                ~source_lesson_subtitle_toggle;
            repeat (7) @(posedge pixel_clk);
            #1;
        end
    endtask

    video_effects_osd #(
        .SCROLL_FRAME_DIV(1)
    ) dut (
        .pixel_clk(pixel_clk),
        .pixel_rst(pixel_rst),
        .frame_boundary(frame_boundary),
        .in_hs(in_hs),
        .in_vs(in_vs),
        .in_de(in_de),
        .in_rgb(in_rgb),
        .source_brightness(source_brightness),
        .source_contrast(source_contrast),
        .source_osd_enable(source_osd_enable),
        .source_subtitle_enable(source_subtitle_enable),
        .source_control_toggle(source_control_toggle),
        .source_zoom_preview_level(source_zoom_preview_level),
        .display_image_idx(4'd1),
        .display_zoom_level(3'd2),
        .display_valid(1'b0), .transition_active(1'b0),
        .source_target_image_idx(4'd1),
        .source_wrong_bitmap(3'd0),.source_state_code(source_state_code),
        .source_state_toggle(source_state_toggle),
        .source_auto_play(1'b1),
        .source_eye_comfort_enable(1'b0),
    .source_volume_level(3'd4), .source_volume_toggle(1'b0),
    .source_speed_level(2'd1), .source_speed_toggle(1'b0),
    .voice_progress(9'd0), .voice_clip(2'd0), .voice_valid(1'b0),
        .source_lesson_subtitle_active(source_lesson_subtitle_active),
        .source_lesson_subtitle_clip(source_lesson_subtitle_clip),
        .source_lesson_subtitle_cue(source_lesson_subtitle_cue),
        .source_lesson_subtitle_toggle(source_lesson_subtitle_toggle),
        .out_hs(out_hs),
        .out_vs(out_vs),
        .out_de(out_de),
        .out_rgb(out_rgb)
    );

    initial begin
        repeat (3) @(posedge pixel_clk);
        @(negedge pixel_clk);
        pixel_rst = 1'b0;

        // Chinese message tables and native 16x16 font rows are deterministic.
        if (dut.status_char(5'd0, 2'd1, 1'b1, 3'sd0, 2'd1, 3'd2, 1'b0) != 8'h80)
            $fatal(1, "Chinese status label does not begin with image");
        if (dut.status_char(5'd5, 2'd1, 1'b1, 3'sd0, 2'd1, 3'd2, 1'b0) != 8'h86 ||
            dut.status_char(5'd16, 2'd1, 1'b1, 3'sd0, 2'd1, 3'd2, 1'b0) != 8'hC0 ||
            dut.status_char(5'd19, 2'd1, 1'b1, 3'sd0, 2'd1, 3'd2, 1'b0) != "1" ||
            dut.status_char(5'd22, 2'd1, 1'b1, 3'sd0, 2'd1, 3'd2, 1'b0) != "%")
            $fatal(14, "zoom status is not 100 percent");
        if (dut.subtitle_char(4'd0, 4'd3) != 8'h90 ||
            dut.subtitle_char(4'd4, 4'd3) != 8'h9F)
            $fatal(2, "quiz subtitle is not request-answer");
        if (dut.subtitle_char(4'd0, 4'd7) != 8'h91 ||
            dut.subtitle_char(4'd7, 4'd7) != 8'hB8)
            $fatal(3, "settings subtitle is not select-parameter");
        if (dut.font_row(8'h80, 4'd1) != 16'h7FFC)
            $fatal(4, "Chinese 16x16 glyph row mismatch");

        // Top-left status background on row 0.
        @(negedge pixel_clk);
        in_de = 1'b1;
        in_rgb = 24'h806040;
        @(posedge pixel_clk);
        @(posedge pixel_clk);
        #1;
        if (out_rgb != 24'h201810)
            $fatal(5, "status background mismatch: %h", out_rgb);
        end_line();

        // Row 1, column 1 belongs to the first Chinese glyph (image).
        for (x = 0; x < 2; x = x + 1) begin
            @(negedge pixel_clk);
            in_de = 1'b1;
            in_rgb = 24'h806040;
            @(posedge pixel_clk);
            @(posedge pixel_clk);
            #1;
            if (x == 1 && out_rgb != 24'hFFFFFF)
                $fatal(6, "Chinese status glyph mismatch: %h", out_rgb);
        end
        end_line();

        // Move below the 16-line status bar and verify the unity default.
        repeat (14)
            one_pixel_line(24'h112233);
        @(negedge pixel_clk);
        in_de = 1'b1;
        in_rgb = 24'h64C800;
        @(posedge pixel_clk);
        @(posedge pixel_clk);
        #1;
        if (out_rgb != 24'h64C800)
            $fatal(7, "unity color path mismatch: %h", out_rgb);
        end_line();

        // A synchronized control request must remain pending until a frame
        // boundary, so one visible frame cannot mix old and new parameters.
        @(negedge pixel_clk);
        source_brightness = 3'sd2;
        source_contrast = 2'd3;
        source_control_toggle = 1'b1;
        repeat (7) @(posedge pixel_clk);
        #1;
        if (!dut.control_pending_valid ||
            dut.brightness_active != 3'sd0 || dut.contrast_active != 2'd1)
            $fatal(8, "video controls changed before frame boundary");

        pulse_frame_boundary();
        #1;
        if (dut.control_pending_valid ||
            dut.brightness_active != 3'sd2 || dut.contrast_active != 2'd3)
            $fatal(8, "video controls did not commit at frame boundary");

        // 1.5x contrast and +32 brightness: 100->118, 200->255, 0->0.
        // The boundary also resets the raster coordinates, so step below the
        // 16-line status bar before checking the unobscured adjusted pixel.
        repeat (16)
            one_pixel_line(24'h112233);
        @(negedge pixel_clk);
        in_de = 1'b1;
        in_rgb = 24'h64C800;
        @(posedge pixel_clk);
        @(posedge pixel_clk);
        #1;
        if (out_rgb != 24'h76FF00)
            $fatal(8, "adjusted/saturated RGB mismatch: %h", out_rgb);
        end_line();

        // SETTINGS zoom feedback shares the same frame-atomic control mailbox.
        // It still appears before the expensive TF reread commits, but never
        // changes halfway through the currently scanned frame.
        @(negedge pixel_clk);
        source_zoom_preview_level = 3'd4;
        source_control_toggle = ~source_control_toggle;
        repeat (7) @(posedge pixel_clk);
        #1;
        dut.state_active = 4'd7;
        dut.state_pending = 4'd7;
        #1;
        if (dut.status_zoom_level != 3'd2 || !dut.control_pending_valid)
            $fatal(15, "zoom preview changed before frame boundary");
        pulse_frame_boundary();
        #1;
        if (dut.status_zoom_level != 3'd4 || dut.control_pending_valid)
            $fatal(15, "zoom preview did not commit at frame boundary");
        dut.state_active = 4'd0;
        dut.state_pending = 4'd0;
        dut.scroll_position = 10'd0;
        dut.scroll_frame_count = 8'd0;

        pulse_frame_boundary();
        #1;
        if (dut.scroll_position != 10'd1)
            $fatal(9, "subtitle did not advance at frame boundary");

        // Narration captions arrive from the audio clock domain as a stable
        // payload plus toggle, then become visible only on a frame boundary.
        publish_lesson_subtitle(1'b1, 2'd0, 5'd0);
        if (!dut.lesson_subtitle_pending_valid ||
            dut.lesson_subtitle_active)
            $fatal(16, "lesson subtitle changed before frame boundary");
        pulse_frame_boundary();
        #1;
        if (!dut.lesson_subtitle_active ||
            dut.lesson_subtitle_clip != 2'd0 ||
            dut.lesson_subtitle_cue != 5'd0)
            $fatal(16, "lesson subtitle did not commit atomically");

        // Caption zero is centered.  Column 15 contains its first real glyph.
        dut.pixel_x = 10'd240;
        dut.pixel_y = 10'd464;
        #1;
        if (!dut.lesson_subtitle_region ||
            dut.lesson_subtitle_code == 8'd0)
            $fatal(17, "lesson subtitle ROM did not expose centered text");

        publish_lesson_subtitle(1'b1, 2'd0, 5'd1);
        if (dut.lesson_subtitle_cue != 5'd0)
            $fatal(18, "lesson cue changed before frame boundary");
        pulse_frame_boundary();
        #1;
        if (dut.lesson_subtitle_cue != 5'd1)
            $fatal(18, "lesson cue did not update at frame boundary");

        publish_lesson_subtitle(1'b0, 2'd0, 5'd1);
        pulse_frame_boundary();
        #1;
        if (dut.lesson_subtitle_active)
            $fatal(19, "lesson subtitle did not clear after narration");

        // The toggle mailbox is sampled first and committed only on a frame
        // boundary, so all Chinese UI text changes atomically.
        publish_state(4'd3);
        if (dut.state_pending != {4'd1, 3'd0, 4'd3} || dut.state_active != 4'd0)
            $fatal(10, "state mailbox did not hold until frame boundary");
        pulse_frame_boundary();
        #1;
        if (dut.state_active != 4'd3 || dut.scroll_position != 10'd0)
            $fatal(11, "quiz state was not committed atomically");

        // Check both blank margins for every scrolling message.
        dut.scroll_position = 10'd640;
        dut.pixel_y = 10'd464;
        for (state_check = 0; state_check <= 9; state_check = state_check + 1) begin
            dut.state_active = state_check;
            first_cell = -1;
            last_cell = -1;
            for (x = 0; x < 256; x = x + 1) begin
                dut.pixel_x = x;
                #1;
                if (dut.subtitle_code != 8'h20) begin
                    if (first_cell < 0) first_cell = x;
                    last_cell = x;
                end
            end
            if (first_cell < 0 ||
                ((first_cell + last_cell) != 255 &&
                 (first_cell + last_cell) != 256))
                $fatal(1, "scrolling text is not centered for state %0d: %0d..%0d",
                       state_check, first_cell, last_cell);
        end
        dut.state_active = 4'd3;
        dut.pixel_x = 10'd88;
        #1;
        if (dut.subtitle_code != 8'h90)
            $fatal(1, "quiz subtitle first glyph moved outside the centered strip");

        // Scroll the centered first glyph to x=0 and check the final RGB pixel.
        @(negedge pixel_clk);
        dut.pixel_x = 10'd0;
        dut.pixel_y = 10'd0;
        dut.scroll_position = 10'd728;
        repeat (464)
            one_pixel_line(24'h204060);
        for (x = 0; x < 4; x = x + 1) begin
            @(negedge pixel_clk);
            in_de = 1'b1;
            in_rgb = 24'h204060;
            @(posedge pixel_clk);
            @(posedge pixel_clk);
            #1;
            if (x == 1 && out_rgb != 24'hFFD54A)
                $fatal(12, "Chinese subtitle glyph mismatch: %h", out_rgb);
        end
        end_line();

        // A complete active frame must retain exactly 640*480 valid pixels.
        pulse_frame_boundary();
        count_before = output_pixels;
        for (y = 0; y < 480; y = y + 1) begin
            for (x = 0; x < 640; x = x + 1) begin
                @(negedge pixel_clk);
                in_de = 1'b1;
                in_rgb = {x[7:0], y[7:0], 8'h55};
                @(posedge pixel_clk);
            end
            end_line();
        end
        @(negedge pixel_clk);
        if (output_pixels - count_before != 307200)
            $fatal(13, "full-frame valid count mismatch: %0d",
                   output_pixels - count_before);

        // RGB and all three timing signals must emerge on the same stage.
        @(negedge pixel_clk);
        dut.pixel_y = 10'd20;
        dut.brightness_active = 3'sd0;
        dut.contrast_active = 2'd1;
        in_rgb = 24'h2468AC;
        in_de = 1'b1;
        in_hs = 1'b1;
        in_vs = 1'b1;
        @(posedge pixel_clk);
        #1;
        if (out_hs || out_vs || out_de)
            $fatal(1, "video timing advanced ahead of RGB");
        @(negedge pixel_clk);
        in_de = 1'b0;
        in_hs = 1'b0;
        in_vs = 1'b0;
        @(posedge pixel_clk);
        #1;
        if (!out_hs || !out_vs || !out_de || out_rgb !== 24'h2468AC)
            $fatal(1, "pipelined video data/timing mismatch: %h", out_rgb);
        @(posedge pixel_clk);
        #1;
        if (out_hs || out_vs || out_de)
            $fatal(1, "video timing pulse did not clear together");

        $display("TEST_PASS tb_video_effects_osd");
        $finish;
    end

    initial begin
        #10000000;
        $fatal(14, "test timeout");
    end
endmodule
