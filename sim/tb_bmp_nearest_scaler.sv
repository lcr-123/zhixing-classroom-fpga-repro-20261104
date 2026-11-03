`timescale 1ns/1ps

module tb_bmp_nearest_scaler;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;
    reg [15:0] source_width = 16'd0;
    reg [15:0] source_height = 16'd0;
    reg [2:0] zoom_level = 3'd2;
    reg source_valid = 1'b0;
    reg [23:0] source_rgb = 24'd0;
    wire output_valid;
    wire [23:0] output_rgb;
    wire source_start;
    wire busy;
    wire done;
    wire source_overrun;

    reg [23:0] captured [0:95];
    integer captured_count = 0;
    integer x;
    integer y;
    integer expected_x;
    integer expected_y;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (output_valid) begin
            if (captured_count >= 48)
                $fatal(1, "scaler emitted beyond the frame boundary");
            captured[captured_count] <= output_rgb;
            captured_count <= captured_count + 1;
        end
    end

    bmp_nearest_scaler #(
        .OUTPUT_WIDTH(8),
        .OUTPUT_HEIGHT(6),
        .MAX_SOURCE_WIDTH(16),
        // Legacy nearest mode keeps its four-clock output schedule. The
        // production filter adds separate RAM-selection and blend stages.
        .EMIT_DIV(4), .FILTER_ENABLE(0)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .source_width(source_width),
        .source_height(source_height),
        .zoom_level(zoom_level),
        .source_valid(source_valid),
        .source_rgb(source_rgb),
        .source_start(source_start),
        .output_valid(output_valid),
        .output_rgb(output_rgb),
        .busy(busy),
        .done(done),
        .source_overrun(source_overrun)
    );

    task automatic begin_case(
        input integer width,
        input integer height,
        input integer zoom,
        input integer reset_first = 1
    );
        begin
            @(negedge clk);
            if (reset_first) begin
                rst = 1'b1;
                repeat (2) @(negedge clk);
            end
            rst = 1'b0;
            captured_count = 0;
            source_width = width;
            source_height = height;
            zoom_level = zoom;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait (source_start);
            @(negedge clk);
        end
    endtask

    // An independent integer reference checks row selection and centered
    // borders for odd dimensions and consecutive zoom changes without reset.
    task automatic reference_case(
        input integer width, input integer height, input integer zoom
    );
        integer crop_w, crop_h, origin_x, origin_y;
        integer active_w, active_h, left_border, top_border;
        integer rx, ry, sx, sy;
        reg [23:0] expected_pixel;
        begin
            crop_w = width;
            crop_h = height;
            active_w = 8;
            active_h = 6;
            left_border = 0;
            top_border = 0;
            case (zoom)
                0: begin active_w = 4; active_h = 3;
                         left_border = 2; top_border = 1; end
                1: begin active_w = 6; active_h = 4;
                         left_border = 1; top_border = 0; end
                3: begin crop_w = (width * 4) / 5;
                         crop_h = (height * 4) / 5; end
                4: begin crop_w = (width * 2) / 3;
                         crop_h = (height * 2) / 3; end
            endcase
            if (crop_w == 0) crop_w = 1;
            if (crop_h == 0) crop_h = 1;
            origin_x = (width - crop_w) / 2;
            origin_y = (height - crop_h) / 2;
            begin_case(width, height, zoom, 0);
            for (ry = 0; ry < height; ry = ry + 1)
                for (rx = 0; rx < width; rx = rx + 1)
                    send_source_pixel(ry, rx);
            finish_case();
            for (ry = 0; ry < 6; ry = ry + 1) begin
                for (rx = 0; rx < 8; rx = rx + 1) begin
                    expected_pixel = 24'd0;
                    if ((rx >= left_border) && (rx < left_border + active_w) &&
                        (ry >= top_border) && (ry < top_border + active_h)) begin
                        sx = origin_x + ((rx - left_border) * crop_w) / active_w;
                        sy = origin_y +
                             (((ry - top_border + 1) * crop_h + active_h - 1) /
                              active_h) - 1;
                        expected_pixel = {sy[7:0], sx[7:0], 8'hA5};
                    end
                    if (captured[ry * 8 + rx] !== expected_pixel)
                        $fatal(1, "reference mismatch zoom=%0d source=%0dx%0d at %0d,%0d: %h expected %h",
                               zoom, width, height, rx, ry,
                               captured[ry * 8 + rx], expected_pixel);
                end
            end
        end
    endtask

    task automatic send_source_pixel(input integer row, input integer col);
        begin
            source_rgb = {row[7:0], col[7:0], 8'hA5};
            source_valid = 1'b1;
            @(negedge clk);
            source_valid = 1'b0;
            // The BMP parser/SD path is intentionally much slower than this
            // unit-level producer.  Keep the synthetic source below the
            // legacy EMIT_DIV=4 drain rate, including 150% row repeats.
            repeat (63) @(negedge clk);
        end
    endtask

    task automatic finish_case;
        begin
            wait (!busy);
            @(posedge clk);
            #1;
            if (captured_count != 48)
                $fatal(1, "scaled pixel count mismatch: %0d", captured_count);
            if (source_overrun)
                $fatal(1, "source row overran scaler output");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);

        // 4x3 to 8x6: every source pixel and row must be duplicated twice.
        begin_case(4, 3, 2);
        for (y = 0; y < 3; y = y + 1)
            for (x = 0; x < 4; x = x + 1)
                send_source_pixel(y, x);
        finish_case();
        for (y = 0; y < 6; y = y + 1) begin
            for (x = 0; x < 8; x = x + 1) begin
                expected_y = y >> 1;
                expected_x = x >> 1;
                if (captured[y * 8 + x] !==
                    {expected_y[7:0], expected_x[7:0], 8'hA5})
                    $fatal(1, "upscale mismatch at %0d,%0d: %h",
                           x, y, captured[y * 8 + x]);
            end
        end

        // 10x9 to 8x6 exercises horizontal and vertical row dropping.
        begin_case(10, 9, 2);
        for (y = 0; y < 9; y = y + 1)
            for (x = 0; x < 10; x = x + 1)
                send_source_pixel(y, x);
        finish_case();
        for (y = 0; y < 6; y = y + 1) begin
            case (y)
                0: expected_y = 1;
                1: expected_y = 2;
                2: expected_y = 4;
                3: expected_y = 5;
                4: expected_y = 7;
                default: expected_y = 8;
            endcase
            for (x = 0; x < 8; x = x + 1) begin
                expected_x = (x * 10) / 8;
                if (captured[y * 8 + x] !==
                    {expected_y[7:0], expected_x[7:0], 8'hA5})
                    $fatal(1, "downscale mismatch at %0d,%0d: %h",
                           x, y, captured[y * 8 + x]);
            end
        end

        // 50% keeps the entire 8x6 source in a centered 4x3 window.  The
        // small test geometry has one leading and two trailing black rows.
        begin_case(8, 6, 0);
        for (y = 0; y < 6; y = y + 1)
            for (x = 0; x < 8; x = x + 1)
                send_source_pixel(y, x);
        finish_case();
        for (y = 0; y < 6; y = y + 1) begin
            for (x = 0; x < 8; x = x + 1) begin
                if ((y >= 1) && (y <= 3) &&
                    (x >= 2) && (x <= 5)) begin
                    expected_y = 1 + ((y - 1) << 1);
                    expected_x = (x - 2) << 1;
                    if (captured[y * 8 + x] !==
                        {expected_y[7:0], expected_x[7:0], 8'hA5})
                        $fatal(1, "50-percent mismatch at %0d,%0d: %h",
                               x, y, captured[y * 8 + x]);
                end else if (captured[y * 8 + x] !== 24'd0) begin
                    $fatal(1, "50-percent border was not black at %0d,%0d",
                           x, y);
                end
            end
        end

        // 150% center-crops 12x9 to 8x6, which maps exactly to the output.
        begin_case(12, 9, 4);
        for (y = 0; y < 9; y = y + 1)
            for (x = 0; x < 12; x = x + 1)
                send_source_pixel(y, x);
        finish_case();
        for (y = 0; y < 6; y = y + 1) begin
            for (x = 0; x < 8; x = x + 1) begin
                expected_y = y + 1;
                expected_x = x + 2;
                if (captured[y * 8 + x] !==
                    {expected_y[7:0], expected_x[7:0], 8'hA5})
                    $fatal(1, "150-percent crop mismatch at %0d,%0d: %h",
                           x, y, captured[y * 8 + x]);
            end
        end

        // The first production card is 320x240.  At 150% its center crop is
        // about 213x160, so one cropped source row must be replayed three
        // times to fill 480 output rows.  This 4x3 analogue catches a missing
        // third replay without making the simulation process a full frame.
        begin_case(4, 3, 4);
        for (y = 0; y < 3; y = y + 1)
            for (x = 0; x < 4; x = x + 1)
                send_source_pixel(y, x);
        finish_case();
        for (y = 0; y < 6; y = y + 1) begin
            expected_y = y / 3;
            for (x = 0; x < 8; x = x + 1) begin
                expected_x = 1 + (x / 4);
                if (captured[y * 8 + x] !==
                    {expected_y[7:0], expected_x[7:0], 8'hA5})
                    $fatal(1, "small-source 150-percent mismatch at %0d,%0d: %h",
                           x, y, captured[y * 8 + x]);
            end
        end

        for (x = 0; x < 5; x = x + 1)
            if (x != 1) reference_case(7, 5, x);
        reference_case(4, 3, 3); // zero crop origin after a nonzero origin
        reference_case(9, 7, 4);
        reference_case(8, 6, 2);

        // Interrupt crop configuration, then restart with a different ratio.
        @(negedge clk);
        source_width = 16'd16;
        source_height = 16'd12;
        zoom_level = 3'd3;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        repeat (3) @(negedge clk);
        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        reference_case(8, 6, 0);

        $display("TEST_PASS tb_bmp_nearest_scaler");
        $finish;
    end

    initial begin
        #2000000;
        $display("DEBUG phase=%0d busy=%b emit_busy=%b write_x=%0d source_row=%0d all_seen=%b out_x=%0d rows_remaining=%0d left=%0d overrun=%b captured=%0d",
                 dut.phase,
                 busy, dut.emit_busy, dut.write_x, dut.source_row,
                 dut.source_all_seen, dut.output_x, dut.active_rows_remaining,
                 dut.rows_left, source_overrun, captured_count);
        $fatal(1, "test timeout");
    end
endmodule
