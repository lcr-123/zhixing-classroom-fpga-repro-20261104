`timescale 1ns/1ps

module tb_audio_waveform_overlay;
    reg pixel_clk = 1'b0;
    reg pixel_rst = 1'b1;
    reg frame_boundary = 1'b0;
    reg in_hs = 1'b0;
    reg in_vs = 1'b0;
    reg in_de = 1'b0;
    reg [23:0] in_rgb = 24'h203040;
    reg overlay_enable = 1'b1;
    reg [3:0] theme_index = 4'd0;
    reg audio_valid = 1'b0;
    reg [23:0] audio_sample = 24'd0;
    wire out_hs;
    wire out_vs;
    wire out_de;
    wire [23:0] out_rgb;
    integer x;
    integer y;
    integer bar_pixels = 0;
    integer low_bar_pixels = 0;
    integer high_bar_pixels = 0;
    integer output_pixels = 0;
    integer capture_x = 0;
    integer capture_y = 0;
    integer palette_mask = 0;
    reg output_de_d = 1'b0;
    reg [7:0] frozen_read_base;
    reg [23:0] captured_rgb [0:55][0:639];

    always #5 pixel_clk = ~pixel_clk;

    function automatic is_bar_color(input [23:0] color);
        begin
            case (color)
                24'h5D95D8, 24'h6CA5E5, 24'h7AB2EC, 24'h879CE2,
                24'h9A87D6, 24'hB77FC5, 24'hD282A8, 24'hE49483,
                24'hE9AD63, 24'hD4C34F: is_bar_color = 1'b1;
                default: is_bar_color = 1'b0;
            endcase
        end
    endfunction

    always @(negedge pixel_clk) begin
        if (out_de) begin
            captured_rgb[capture_y][capture_x] = out_rgb;
            capture_x = capture_x + 1;
            output_pixels = output_pixels + 1;
            if (is_bar_color(out_rgb)) begin
                bar_pixels = bar_pixels + 1;
                case (out_rgb)
                    24'h5D95D8: palette_mask = palette_mask | 10'b0000000001;
                    24'h6CA5E5: palette_mask = palette_mask | 10'b0000000010;
                    24'h7AB2EC: palette_mask = palette_mask | 10'b0000000100;
                    24'h879CE2: palette_mask = palette_mask | 10'b0000001000;
                    24'h9A87D6: palette_mask = palette_mask | 10'b0000010000;
                    24'hB77FC5: palette_mask = palette_mask | 10'b0000100000;
                    24'hD282A8: palette_mask = palette_mask | 10'b0001000000;
                    24'hE49483: palette_mask = palette_mask | 10'b0010000000;
                    24'hE9AD63: palette_mask = palette_mask | 10'b0100000000;
                    24'hD4C34F: palette_mask = palette_mask | 10'b1000000000;
                endcase
            end
        end else if (output_de_d) begin
            capture_x = 0;
            capture_y = capture_y + 1;
        end
        output_de_d = out_de;
    end

    task automatic reset_capture;
        begin
            bar_pixels = 0;
            output_pixels = 0;
            capture_x = 0;
            capture_y = 0;
            palette_mask = 0;
            output_de_d = out_de;
        end
    endtask

    task automatic send_audio(input [23:0] value);
        begin
            @(negedge pixel_clk);
            audio_sample = value;
            audio_valid = 1'b1;
            @(negedge pixel_clk);
            audio_valid = 1'b0;
        end
    endtask

    task automatic end_line;
        begin
            @(negedge pixel_clk);
            in_de = 1'b0;
            repeat (2) @(posedge pixel_clk);
        end
    endtask

    task automatic capture_frame;
        begin
            for (y = 0; y < 56; y = y + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    @(negedge pixel_clk);
                    in_de = 1'b1;
                    in_rgb = 24'h8090A0;
                end
                end_line();
            end
            @(negedge pixel_clk);
            repeat (3) @(posedge pixel_clk);
        end
    endtask

    task automatic pulse_frame_boundary;
        begin
            @(negedge pixel_clk);
            frame_boundary = 1'b1;
            @(negedge pixel_clk);
            frame_boundary = 1'b0;
        end
    endtask

    audio_waveform_overlay #(
        .FRAME_WIDTH(640),
        .FRAME_HEIGHT(56),
        .WAVE_WIDTH(640),
        .WAVE_TOP(2),
        .WAVE_HEIGHT(32),
        .SNAPSHOT_FRAME_DIV(4)
    ) dut (
        .pixel_clk(pixel_clk),
        .pixel_rst(pixel_rst),
        .frame_boundary(frame_boundary),
        .in_hs(in_hs),
        .in_vs(in_vs),
        .in_de(in_de),
        .in_rgb(in_rgb),
        .overlay_enable(overlay_enable),
        .theme_index(theme_index),
        .audio_valid(audio_valid),
        .audio_sample(audio_sample),
        .out_hs(out_hs),
        .out_vs(out_vs),
        .out_de(out_de),
        .out_rgb(out_rgb)
    );

    initial begin
        repeat (3) @(negedge pixel_clk);
        pixel_rst = 1'b0;

        send_audio(24'h7FFFFF);
        if (dut.sample_memory[0] != 8'h7F)
            $fatal(1, "maximum positive sample did not saturate");
        send_audio(24'h800000);
        if (dut.sample_memory[1] != 8'h80)
            $fatal(1, "minimum negative sample did not saturate");

        @(negedge pixel_clk);
        pixel_rst = 1'b1;
        repeat (2) @(negedge pixel_clk);
        pixel_rst = 1'b0;

        for (x = 0; x < 256; x = x + 1)
            send_audio(24'd0);
        pulse_frame_boundary();
        frozen_read_base = dut.sample_read_base;

        reset_capture();
        capture_frame();
        low_bar_pixels = bar_pixels;

        if (dut.sample_read_base != frozen_read_base)
            $fatal(1, "waveform read base changed within a frame");
        if (output_pixels != 35840)
            $fatal(1, "active pixel count changed: %0d", output_pixels);
        if ((low_bar_pixels == 0) || (low_bar_pixels >= 1500))
            $fatal(1, "quiet bar pixel count invalid: %0d", low_bar_pixels);
        if (captured_rgb[18][3] != 24'h5D95D8)
            $fatal(1, "quiet center bar or first palette color missing");
        if (captured_rgb[18][0] != 24'h404850)
            $fatal(1, "bar gap or panel dimming failed");
        if (captured_rgb[1][1] != 24'h8090A0)
            $fatal(1, "RGB changed above waveform region");
        if (captured_rgb[39][1] != 24'h8090A0)
            $fatal(1, "RGB changed below waveform region");
        if (captured_rgb[10][639] != 24'h404850)
            $fatal(1, "waveform panel did not extend across the frame");

        for (x = 0; x < 256; x = x + 1)
            send_audio(24'h7FFFFF);
        pulse_frame_boundary();

        reset_capture();
        capture_frame();
        high_bar_pixels = bar_pixels;

        if (output_pixels != 35840)
            $fatal(1, "high-level active pixel count changed: %0d", output_pixels);
        if (high_bar_pixels <= (low_bar_pixels * 4))
            $fatal(1, "bar height did not follow audio level: low=%0d high=%0d",
                   low_bar_pixels, high_bar_pixels);
        if (palette_mask != 10'b1111111111)
            $fatal(1, "lesson palette incomplete: %b", palette_mask);
        if (captured_rgb[4][3] != 24'h5D95D8)
            $fatal(1, "rounded bar top cap missing");
        if (captured_rgb[4][2] != 24'h404850)
            $fatal(1, "bar top cap was not narrowed");
        if (captured_rgb[5][2] != 24'h5D95D8)
            $fatal(1, "bar body width incorrect");
        if ((dut.themed_bar_color(4'd0, 10'd0) != 24'h5D95D8) ||
            (dut.themed_bar_color(4'd0, 10'd639) != 24'hD4C34F))
            $fatal(1, "lake-and-mountain lesson theme mapping incorrect");
        if ((dut.themed_bar_color(4'd1, 10'd0) != 24'h287A58) ||
            (dut.themed_bar_color(4'd1, 10'd639) != 24'h468FD0))
            $fatal(1, "forest-river theme mapping incorrect");
        if ((dut.themed_bar_color(4'd2, 10'd0) != 24'h5F7F7A) ||
            (dut.themed_bar_color(4'd2, 10'd639) != 24'h7C98AB))
            $fatal(1, "village-river theme mapping incorrect");
        theme_index = 4'd1;
        repeat (2) @(negedge pixel_clk);
        if (dut.frame_theme_index != 4'd0)
            $fatal(1, "theme changed before a frame boundary");
        pulse_frame_boundary();
        if (dut.frame_theme_index != 4'd1)
            $fatal(1, "forest theme was not committed at frame boundary");
        theme_index = 4'd2;
        pulse_frame_boundary();
        if (dut.frame_theme_index != 4'd2)
            $fatal(1, "village theme was not committed at frame boundary");
        if (out_de || (out_rgb != 24'd0))
            $fatal(1, "blanking output was not black");

        overlay_enable = 1'b0;
        theme_index = 4'd3;
        pulse_frame_boundary();
        reset_capture();
        capture_frame();
        if (bar_pixels != 0)
            $fatal(1, "exercise page still rendered waveform bars");
        if ((captured_rgb[18][0] != 24'h8090A0) ||
            (captured_rgb[18][3] != 24'h8090A0))
            $fatal(1, "exercise page still rendered the waveform panel");

        @(negedge pixel_clk);
        pixel_rst = 1'b1;
        repeat (2) @(negedge pixel_clk);
        pixel_rst = 1'b0;
        pulse_frame_boundary();
        frozen_read_base = dut.sample_read_base;
        send_audio(24'h010000);
        repeat (3) pulse_frame_boundary();
        if (dut.sample_read_base != frozen_read_base)
            $fatal(1, "waveform snapshot refreshed before four frames");
        pulse_frame_boundary();
        if (dut.sample_read_base != dut.sample_write_ptr)
            $fatal(1, "waveform snapshot did not refresh on fourth frame");

        // The waveform stage must preserve every pixel below its panel,
        // including the old subtitle region, for every learning theme.
        overlay_enable=1;
        for (integer page=0; page<3; page=page+1) begin
            theme_index=page;
            pulse_frame_boundary(); reset_capture(); capture_frame();
            for (integer row=34; row<56; row=row+1)
                for (integer col=0; col<640; col=col+1)
                    if (captured_rgb[row][col] !== 24'h8090A0)
                        $fatal(1,"waveform overwrote subtitle/gap pixel %0d,%0d",col,row);
        end
        $display("TEST_PASS tb_audio_waveform_overlay: wave, palettes, untouched subtitle and gap");
        $finish;
    end

    initial begin
        #6000000;
        $fatal(1, "test timeout");
    end
endmodule
