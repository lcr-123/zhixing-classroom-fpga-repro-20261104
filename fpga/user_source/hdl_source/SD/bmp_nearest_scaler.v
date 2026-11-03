`timescale 1ns/1ps

module bmp_nearest_scaler #(
    parameter integer OUTPUT_WIDTH     = 640,
    parameter integer OUTPUT_HEIGHT    = 480,
    parameter integer MAX_SOURCE_WIDTH = 1280,
    parameter integer ADDRESS_WIDTH    = 12,
    parameter integer EMIT_DIV         = 6,
    parameter integer FILTER_ENABLE    = 1,
    parameter integer SOURCE_ROI_ENABLE = 0,
    parameter integer ZOOM_FOCUS_LEFT   = 0
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [15:0] source_width,
    input  wire [15:0] source_height,
    input  wire [2:0]  zoom_level,
    input  wire        source_valid,
    input  wire [23:0] source_rgb,
    output reg         source_start,
    output reg         output_valid,
    output reg  [23:0] output_rgb,
    output reg         busy,
    output reg         done,
    output reg         source_overrun,
    output wire [15:0] source_first_row,
    output wire [15:0] source_row_count
);

localparam [2:0] PH_IDLE        = 3'd0;
localparam [2:0] PH_LEAD_BORDER = 3'd1;
localparam [2:0] PH_SOURCE_WAIT = 3'd2;
localparam [2:0] PH_SOURCE      = 3'd3;
localparam [2:0] PH_TAIL_BORDER = 3'd4;
localparam [2:0] PH_CONFIG      = 3'd5;
localparam [2:0] PH_CONFIG_DONE = 3'd6;
localparam integer TOTAL_PIXELS = OUTPUT_WIDTH * OUTPUT_HEIGHT;
localparam integer SOURCE_ADDRESS_WIDTH = $clog2(MAX_SOURCE_WIDTH);
localparam integer PIXEL_COUNT_BITS = (TOTAL_PIXELS > 1) ?
                                      $clog2(TOTAL_PIXELS + 1) : 1;
localparam [PIXEL_COUNT_BITS-1:0] FRAME_PIXELS = TOTAL_PIXELS;
localparam [PIXEL_COUNT_BITS-1:0] LAST_FRAME_PIXEL = TOTAL_PIXELS - 1;

// Three rotating source rows keep the two filter inputs immutable while
// the next source row is arriving. No producer backpressure is introduced.
reg [23:0] line0 [0:MAX_SOURCE_WIDTH-1]
    /* fehdl force_ram=1, ram_style="bram" */;
reg [23:0] line1 [0:MAX_SOURCE_WIDTH-1]
    /* fehdl force_ram=1, ram_style="bram" */;
reg [23:0] line2 [0:MAX_SOURCE_WIDTH-1]
    /* fehdl force_ram=1, ram_style="bram" */;
reg [23:0] data0, data1, data2;
reg previous_line_available;
reg [23:0] left_current, left_previous;
reg [23:0] right_current, right_previous;
reg [23:0] horizontal_current, horizontal_previous;
reg [23:0] filtered_data;
reg [15:0] output_y_remainder;
reg [17:0] output_y_sum;
reg [15:0] output_y_next;
reg [2:0] horizontal_weight, vertical_weight;

// Four fractional phases plus exact endpoints, rounded to nearest quarter.
// Shift/add comparisons and 10-bit blends avoid division and DSP blocks.
function [2:0] quarter_weight;
    input [15:0] remainder_value;
    input [15:0] denominator;
    reg [18:0] r, d;
    begin
        r = {remainder_value, 3'b000};
        d = {3'b000, denominator};
        quarter_weight = (r >= ((d << 3) - d)) ? 3'd4 :
                         (r >= ((d << 2) + d)) ? 3'd3 :
                         (r >= ((d << 1) + d)) ? 3'd2 :
                         (r >= d) ? 3'd1 : 3'd0;
    end
endfunction
function [7:0] blend_channel;
    input [7:0] a, b;
    input [2:0] weight_b;
    reg [9:0] aa, bb, result;
    begin
        aa = {2'b00,a}; bb = {2'b00,b};
        case (weight_b)
            0: result = aa << 2;
            1: result = (aa << 1) + aa + bb;
            2: result = (aa + bb) << 1;
            3: result = aa + (bb << 1) + bb;
            default: result = bb << 2;
        endcase
        blend_channel = (result + 10'd2) >> 2;
    end
endfunction
function [23:0] blend_rgb;
    input [23:0] a, b;
    input [2:0] weight_b;
    begin
        blend_rgb = {blend_channel(a[23:16],b[23:16],weight_b),
                     blend_channel(a[15:8],b[15:8],weight_b),
                     blend_channel(a[7:0],b[7:0],weight_b)};
    end
endfunction

reg [2:0]  phase;
reg [15:0] width_latched;
reg [15:0] height_latched;
reg [15:0] crop_width;
reg [15:0] crop_height;
reg [17:0] crop_height_x2;
reg [17:0] crop_height_x3;
reg [15:0] crop_x_start;
reg [15:0] crop_y_start;
reg [15:0] active_width;
reg [15:0] active_height;
reg [15:0] border_left;

reg [15:0] penultimate_source_x;
reg [15:0] write_x;
reg [15:0] source_row;
reg [15:0] rows_before_crop;
reg [15:0] crop_rows_remaining;
assign source_first_row = SOURCE_ROI_ENABLE ? crop_y_start : 16'd0;
assign source_row_count = SOURCE_ROI_ENABLE ? crop_height : height_latched;
reg        current_source_row_in_crop;
reg        write_line_end;
reg        single_pixel_line;
reg [1:0]  write_bank;
reg        source_all_seen;
reg [15:0] vertical_accumulator;
reg [17:0] vertical_sum_precalc /* fehdl keep="true" */;
reg [2:0]  rows_for_source_precalc;
reg [15:0] vertical_remainder_precalc;

reg        emit_busy;
reg [1:0]  read_bank;
reg [SOURCE_ADDRESS_WIDTH-1:0] read_address;
reg [SOURCE_ADDRESS_WIDTH-1:0] read_address_right;
reg [15:0] source_x;
reg [15:0] horizontal_accumulator;
reg [17:0] horizontal_sum_precalc;
reg [2:0]  source_x_step_precalc;
reg [15:0] horizontal_remainder_precalc;
reg [15:0] output_x;
reg [15:0] active_rows_remaining;
reg [2:0]  rows_left;
reg [1:0]  prefetch_count;
reg [7:0]  emit_count;
reg [PIXEL_COUNT_BITS-1:0] output_pixel_count;
reg [PIXEL_COUNT_BITS-1:0] black_pixels_remaining;
reg [17:0] config_remainder_x;
reg [17:0] config_remainder_y;
reg [15:0] config_quotient_x;
reg [15:0] config_quotient_y;
reg [2:0]  config_divisor;

wire [15:0] configured_crop_width =
    (config_quotient_x == 16'd0) ? 16'd1 : config_quotient_x;
wire [15:0] configured_crop_height =
    (config_quotient_y == 16'd0) ? 16'd1 : config_quotient_y;

// The first two emit slots read left and right from each immutable row.
wire [23:0] current_data = (read_bank == 0) ? data0 :
                                   (read_bank == 1) ? data1 : data2;
wire [23:0] previous_data = (read_bank == 0) ? data2 :
                                    (read_bank == 1) ? data0 : data1;
reg read_right;
localparam integer LINE_ADDRESS_WIDTH = SOURCE_ADDRESS_WIDTH;
wire [LINE_ADDRESS_WIDTH-1:0] write_memory_address = write_x;
wire [LINE_ADDRESS_WIDTH-1:0] crop_x_start_address = crop_x_start[LINE_ADDRESS_WIDTH-1:0];
wire [LINE_ADDRESS_WIDTH-1:0] source_x_address = source_x[LINE_ADDRESS_WIDTH-1:0];
wire [LINE_ADDRESS_WIDTH-1:0] source_x_step_address = source_x_step_precalc;
wire [LINE_ADDRESS_WIDTH-1:0] next_read_address =
    crop_x_start_address + source_x_address + source_x_step_address;
wire [LINE_ADDRESS_WIDTH-1:0] next_read_address_right =
    next_read_address + {{(LINE_ADDRESS_WIDTH-1){1'b0}}, 1'b1};
// Prepare both addresses when advancing the output pixel. Keep the carry
// chain out of the high-fanout synchronous BRAM address path.
wire [LINE_ADDRESS_WIDTH-1:0] filter_address =
    read_right ? read_address_right : read_address;
wire [23:0] filtered_rgb = blend_rgb(horizontal_previous, horizontal_current,
    previous_line_available ? vertical_weight : 3'd4);

// Register the accumulator sum one stage before the threshold/subtract tree.
// Source pixels arrive far more slowly than sd_card_clk, so this pipeline has
// ample time to settle before each source-row end while removing the active
// height adder from the 100 MHz remainder-register path.
wire [17:0] vertical_sum = vertical_sum_precalc;
wire [2:0] rows_for_source_calc =
    (vertical_sum >= crop_height_x3) ? 3'd3 :
    (vertical_sum >= crop_height_x2) ? 3'd2 :
    (vertical_sum >= {2'b0, crop_height}) ? 3'd1 : 3'd0;
wire [17:0] vertical_remainder_calc =
    (rows_for_source_calc == 3'd3) ?
        vertical_sum - crop_height_x3 :
    (rows_for_source_calc == 3'd2) ?
        vertical_sum - crop_height_x2 :
    (rows_for_source_calc == 3'd1) ?
        vertical_sum - {2'b0, crop_height} : vertical_sum;

reg active_output_pixel;
reg last_active_output_pixel;
wire [17:0] horizontal_sum = horizontal_sum_precalc;
wire [2:0] source_x_step_calc =
    (horizontal_sum >= ({2'b0, active_width} << 2)) ? 3'd4 :
    (horizontal_sum >= ({2'b0, active_width} * 3)) ? 3'd3 :
    (horizontal_sum >= ({2'b0, active_width} << 1)) ? 3'd2 :
    (horizontal_sum >= {2'b0, active_width}) ? 3'd1 : 3'd0;
wire [17:0] horizontal_remainder_calc =
    (source_x_step_calc == 3'd4) ?
        horizontal_sum - ({2'b0, active_width} << 2) :
    (source_x_step_calc == 3'd3) ?
        horizontal_sum - ({2'b0, active_width} * 3) :
    (source_x_step_calc == 3'd2) ?
        horizontal_sum - ({2'b0, active_width} << 1) :
    (source_x_step_calc == 3'd1) ?
        horizontal_sum - {2'b0, active_width} : horizontal_sum;

always @(posedge clk) begin
    active_output_pixel <= !rst &&
        (output_x >= border_left) &&
        (output_x < (border_left + active_width));
    last_active_output_pixel <= !rst &&
        (output_x + 16'd1 >= (border_left + active_width));
    read_right <= !rst && FILTER_ENABLE && (phase == PH_SOURCE) &&
                  emit_busy && (prefetch_count == 0) && (emit_count == 0) &&
                  (source_x + 16'd1 < crop_width);
    if ((phase == PH_SOURCE) && source_valid && (write_bank == 0))
        line0[write_memory_address] <= source_rgb;
    if ((phase == PH_SOURCE) && source_valid && (write_bank == 1))
        line1[write_memory_address] <= source_rgb;
    if ((phase == PH_SOURCE) && source_valid && (write_bank == 2))
        line2[write_memory_address] <= source_rgb;
    data0 <= line0[filter_address];
    data1 <= line1[filter_address];
    data2 <= line2[filter_address];
    // RAM result for slot 0 is available at slot 1; slot 1's result at 2.
    if (emit_count == 1) begin
        left_current <= current_data;
        left_previous <= previous_data;
    end
    if (emit_count == 2) begin
        right_current <= current_data;
        right_previous <= previous_data;
    end
    if (emit_count == 3) begin
        horizontal_current <= blend_rgb(left_current,right_current,horizontal_weight);
        horizontal_previous <= blend_rgb(left_previous,right_previous,horizontal_weight);
    end
    if (emit_count == 4) begin
        filtered_data <= filtered_rgb;
    end
    horizontal_weight <= (crop_width > active_width) ? 3'd2 :
        quarter_weight(horizontal_accumulator, active_width);
    vertical_weight <= (crop_height > active_height) ? 3'd2 :
        quarter_weight(output_y_next, active_height);
    output_y_sum <= {2'b00,output_y_remainder} + {2'b00,crop_height};
    // Keep an exact integer coordinate at denominator (weight 4).
    output_y_next <=
        (output_y_sum > ({2'b00,active_height} << 2)) ?
            output_y_sum - ({2'b00,active_height} << 2) :
        (output_y_sum > ({2'b00,active_height} * 3)) ?
            output_y_sum - ({2'b00,active_height} * 3) :
        (output_y_sum > ({2'b00,active_height} << 1)) ?
            output_y_sum - ({2'b00,active_height} << 1) :
        (output_y_sum > {2'b00,active_height}) ?
            output_y_sum - {2'b00,active_height} : output_y_sum;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        phase <= PH_IDLE;
        width_latched <= 16'd0;
        height_latched <= 16'd0;
        crop_width <= 16'd1;
        crop_height <= 16'd1;
        crop_height_x2 <= 18'd2;
        crop_height_x3 <= 18'd3;
        crop_x_start <= 16'd0;
        crop_y_start <= 16'd0;
        active_width <= OUTPUT_WIDTH;
        active_height <= OUTPUT_HEIGHT;
        border_left <= 16'd0;
        penultimate_source_x <= 16'd0;
        write_x <= 16'd0;
        source_row <= 16'd0;
        rows_before_crop <= 16'd0;
        crop_rows_remaining <= 16'd1;
        current_source_row_in_crop <= 1'b1;
        write_line_end <= 1'b1;
        single_pixel_line <= 1'b1;
        write_bank <= 2'd0;
        source_all_seen <= 1'b0;
        vertical_accumulator <= 16'd0;
        output_y_remainder <= 16'd0;
        previous_line_available <= 1'b0;
        vertical_sum_precalc <= 18'd0;
        rows_for_source_precalc <= 3'd0;
        vertical_remainder_precalc <= 16'd0;
        emit_busy <= 1'b0;
        read_bank <= 2'd0;
        read_address <= 16'd0;
        read_address_right <= 16'd1;
        source_x <= 16'd0;
        horizontal_accumulator <= 16'd0;
        horizontal_sum_precalc <= 18'd0;
        source_x_step_precalc <= 3'd0;
        horizontal_remainder_precalc <= 16'd0;
        output_x <= 16'd0;
        active_rows_remaining <= OUTPUT_HEIGHT;
        rows_left <= 3'd0;
        prefetch_count <= 2'd0;
        emit_count <= 8'd0;
        output_pixel_count <= {PIXEL_COUNT_BITS{1'b0}};
        black_pixels_remaining <= {PIXEL_COUNT_BITS{1'b0}};
        config_remainder_x <= 18'd0;
        config_remainder_y <= 18'd0;
        config_quotient_x <= 16'd0;
        config_quotient_y <= 16'd0;
        config_divisor <= 3'd1;
        source_start <= 1'b0;
        output_valid <= 1'b0;
        output_rgb <= 24'd0;
        busy <= 1'b0;
        done <= 1'b0;
        source_overrun <= 1'b0;
    end else begin
        source_start <= 1'b0;
        output_valid <= 1'b0;
        done <= 1'b0;

        if (start) begin
            width_latched <= source_width;
            height_latched <= source_height;
            penultimate_source_x <= (source_width <= 16'd1) ?
                                     16'd0 : source_width - 16'd2;
            write_x <= 16'd0;
            source_row <= 16'd0;
            write_line_end <= (source_width <= 16'd1);
            single_pixel_line <= (source_width <= 16'd1);
            write_bank <= 2'd0;
            source_all_seen <= 1'b0;
            vertical_accumulator <= 16'd0;
            output_y_remainder <= 16'd0;
            previous_line_available <= 1'b0;
            vertical_sum_precalc <= 18'd0;
            horizontal_sum_precalc <= 18'd0;
            emit_busy <= 1'b0;
            active_rows_remaining <= 16'd0;
            rows_left <= 3'd0;
            prefetch_count <= 2'd0;
            emit_count <= 8'd0;
            output_pixel_count <= {PIXEL_COUNT_BITS{1'b0}};
            busy <= 1'b1;
            source_overrun <= 1'b0;

            case (zoom_level)
                3'd0: begin // 50%: full source centered in a half-size window
                    crop_width <= source_width;
                    crop_height <= source_height;
                    crop_height_x2 <= {1'b0, source_height, 1'b0};
                    crop_height_x3 <= {1'b0, source_height, 1'b0} +
                                      {2'b0, source_height};
                    crop_x_start <= 16'd0;
                    crop_y_start <= 16'd0;
                    rows_before_crop <= 16'd0;
                    crop_rows_remaining <= source_height;
                    current_source_row_in_crop <= (source_height != 16'd0);
                    active_width <= OUTPUT_WIDTH / 2;
                    active_height <= OUTPUT_HEIGHT / 2;
                    border_left <= OUTPUT_WIDTH / 4;
                    black_pixels_remaining <=
                        (OUTPUT_HEIGHT / 4) * OUTPUT_WIDTH;
                    phase <= ((OUTPUT_HEIGHT / 4) == 0) ?
                             PH_SOURCE_WAIT : PH_LEAD_BORDER;
                end
                3'd1: begin // 75%
                    crop_width <= source_width;
                    crop_height <= source_height;
                    crop_height_x2 <= {1'b0, source_height, 1'b0};
                    crop_height_x3 <= {1'b0, source_height, 1'b0} +
                                      {2'b0, source_height};
                    crop_x_start <= 16'd0;
                    crop_y_start <= 16'd0;
                    rows_before_crop <= 16'd0;
                    crop_rows_remaining <= source_height;
                    current_source_row_in_crop <= (source_height != 16'd0);
                    active_width <= (OUTPUT_WIDTH * 3) / 4;
                    active_height <= (OUTPUT_HEIGHT * 3) / 4;
                    border_left <= OUTPUT_WIDTH / 8;
                    black_pixels_remaining <=
                        (OUTPUT_HEIGHT / 8) * OUTPUT_WIDTH;
                    phase <= ((OUTPUT_HEIGHT / 8) == 0) ?
                             PH_SOURCE_WAIT : PH_LEAD_BORDER;
                end
                3'd3: begin // 125%: crop 80% of the source
                    config_remainder_x <= {source_width, 2'b00};
                    config_remainder_y <= {source_height, 2'b00};
                    config_quotient_x <= 16'd0;
                    config_quotient_y <= 16'd0;
                    config_divisor <= 3'd5;
                    rows_before_crop <= 16'd0;
                    crop_rows_remaining <= 16'd0;
                    current_source_row_in_crop <= 1'b0;
                    active_width <= OUTPUT_WIDTH;
                    active_height <= OUTPUT_HEIGHT;
                    border_left <= 16'd0;
                    black_pixels_remaining <= {PIXEL_COUNT_BITS{1'b0}};
                    phase <= PH_CONFIG;
                end
                3'd4: begin // 150%: crop two thirds of the source
                    config_remainder_x <= {1'b0, source_width, 1'b0};
                    config_remainder_y <= {1'b0, source_height, 1'b0};
                    config_quotient_x <= 16'd0;
                    config_quotient_y <= 16'd0;
                    config_divisor <= 3'd3;
                    rows_before_crop <= 16'd0;
                    crop_rows_remaining <= 16'd0;
                    current_source_row_in_crop <= 1'b0;
                    active_width <= OUTPUT_WIDTH;
                    active_height <= OUTPUT_HEIGHT;
                    border_left <= 16'd0;
                    black_pixels_remaining <= {PIXEL_COUNT_BITS{1'b0}};
                    phase <= PH_CONFIG;
                end
                default: begin // 100%
                    crop_width <= source_width;
                    crop_height <= source_height;
                    crop_height_x2 <= {1'b0, source_height, 1'b0};
                    crop_height_x3 <= {1'b0, source_height, 1'b0} +
                                      {2'b0, source_height};
                    crop_x_start <= 16'd0;
                    crop_y_start <= 16'd0;
                    rows_before_crop <= 16'd0;
                    crop_rows_remaining <= source_height;
                    current_source_row_in_crop <= (source_height != 16'd0);
                    active_width <= OUTPUT_WIDTH;
                    active_height <= OUTPUT_HEIGHT;
                    border_left <= 16'd0;
                    black_pixels_remaining <= {PIXEL_COUNT_BITS{1'b0}};
                    phase <= PH_SOURCE_WAIT;
                end
            endcase
        end else if (busy) begin
            case (phase)
                // Exact constant division is intentionally spread over several
                // clocks. The SDRAM writer is already waiting, so this removes
                // the long 100 MHz source-size-to-crop combinational path with
                // no visible partial frame and negligible load-time impact.
                PH_CONFIG: begin
                    if (config_remainder_x >= config_divisor) begin
                        config_remainder_x <= config_remainder_x - config_divisor;
                        config_quotient_x <= config_quotient_x + 1'b1;
                    end
                    if (config_remainder_y >= config_divisor) begin
                        config_remainder_y <= config_remainder_y - config_divisor;
                        config_quotient_y <= config_quotient_y + 1'b1;
                    end
                    if ((config_remainder_x < config_divisor) &&
                        (config_remainder_y < config_divisor)) begin
                        phase <= PH_CONFIG_DONE;
                    end
                end

                PH_CONFIG_DONE: begin
                        crop_width <= configured_crop_width;
                        crop_height <= configured_crop_height;
                        crop_height_x2 <=
                            {1'b0, configured_crop_height, 1'b0};
                        crop_height_x3 <=
                            {1'b0, configured_crop_height, 1'b0} +
                            {2'b0, configured_crop_height};
                        // Course text is in the left panel. Anchor only the
                        // enlarged window there; reduced images keep their
                        // full source and centered borders. Vertical bounds
                        // and the reader's row ROI remain identical.
                        crop_x_start <= ZOOM_FOCUS_LEFT ? 16'd0 :
                            (width_latched - configured_crop_width) >> 1;
                        crop_y_start <=
                            (height_latched - configured_crop_height) >> 1;
                        crop_rows_remaining <= configured_crop_height;
                        // PH_SOURCE_WAIT initializes the crop gate from the
                        // registered origin, separating subtract and compare.
                        phase <= PH_SOURCE_WAIT;
                end

                PH_LEAD_BORDER: begin
                    if (emit_count == EMIT_DIV - 1) begin
                        emit_count <= 8'd0;
                        output_valid <= 1'b1;
                        output_rgb <= 24'd0;
                        output_pixel_count <= output_pixel_count + 1'b1;
                        if (black_pixels_remaining <= 1) begin
                            black_pixels_remaining <= {PIXEL_COUNT_BITS{1'b0}};
                            active_rows_remaining <= active_height;
                            vertical_sum_precalc <= {2'b0, active_height};
                            source_start <= 1'b1;
                            phase <= PH_SOURCE;
                        end else begin
                            black_pixels_remaining <=
                                black_pixels_remaining - 1'b1;
                        end
                    end else begin
                        emit_count <= emit_count + 1'b1;
                    end
                end

                PH_SOURCE_WAIT: begin
                    rows_before_crop <= SOURCE_ROI_ENABLE ? 16'd0 : crop_y_start;
                    current_source_row_in_crop <= (SOURCE_ROI_ENABLE || crop_y_start == 16'd0) &&
                                                  (crop_height != 16'd0);
                    active_rows_remaining <= active_height;
                    vertical_sum_precalc <= {2'b0, active_height};
                    source_start <= 1'b1;
                    phase <= PH_SOURCE;
                end

                PH_SOURCE: begin
                    // EMIT_DIV leaves several clocks between output pixels.
                    // Precompute and register the Bresenham step/remaining
                    // fraction so the emit edge does not contain both the
                    // wide compare chain and the following address adder.
                    // Keep both horizontal preparation stages free-running in
                    // PH_SOURCE.  Gating them with emit_busy/prefetch lets the
                    // synthesizer fold end-of-line control (including
                    // output_x) into their data muxes, recreating a long path.
                    // The registered values are consumed only on emit edges.
                    horizontal_sum_precalc <=
                        {2'b0, horizontal_accumulator} +
                        {2'b0, crop_width};
                    source_x_step_precalc <= source_x_step_calc;
                    horizontal_remainder_precalc <=
                        horizontal_remainder_calc[15:0];
                    vertical_sum_precalc <=
                        {2'b0, vertical_accumulator} +
                        {2'b0, active_height};
                    rows_for_source_precalc <= rows_for_source_calc;
                    vertical_remainder_precalc <=
                        vertical_remainder_calc[15:0];

                    if (source_valid) begin
                        if (write_line_end) begin
                            write_x <= 16'd0;
                            write_line_end <= single_pixel_line;
                            write_bank <= (write_bank == 2'd2) ? 2'd0 : write_bank + 1'b1;

                            if (current_source_row_in_crop) begin
                                vertical_accumulator <=
                                    vertical_remainder_precalc;
                                if (rows_for_source_precalc != 3'd0) begin
                                    if (emit_busy) begin
                                        source_overrun <= 1'b1;
                                    end else begin
                                        emit_busy <= 1'b1;
                                        read_bank <= write_bank;
                                        previous_line_available <=
                                            (crop_rows_remaining != crop_height);
                                        read_address <= crop_x_start_address;
                                        read_address_right <= crop_x_start_address + 1'b1;
                                        source_x <= 16'd0;
                                        horizontal_accumulator <= 16'd0;
                                        output_x <= 16'd0;
                                        rows_left <= rows_for_source_precalc;
                                        prefetch_count <= 2'd2;
                                        emit_count <= 8'd0;
                                    end
                                end
                            end

                            // Advance a simple run-length crop gate once per
                            // input row. This keeps crop-height arithmetic out
                            // of the high-fanout emit-control enable path.
                            if (current_source_row_in_crop) begin
                                if (crop_rows_remaining != 16'd0)
                                    crop_rows_remaining <=
                                        crop_rows_remaining - 16'd1;
                                current_source_row_in_crop <=
                                    (crop_rows_remaining > 16'd1);
                            end else if (rows_before_crop != 16'd0) begin
                                rows_before_crop <= rows_before_crop - 16'd1;
                                if ((rows_before_crop == 16'd1) &&
                                    (crop_rows_remaining != 16'd0))
                                    current_source_row_in_crop <= 1'b1;
                            end

                            if (SOURCE_ROI_ENABLE ?
                                (current_source_row_in_crop && crop_rows_remaining <= 16'd1) :
                                (source_row + 16'd1 >= height_latched))
                                source_all_seen <= 1'b1;
                            else
                                source_row <= source_row + 16'd1;
                        end else begin
                            write_x <= write_x + 1'b1;
                            write_line_end <= (write_x == penultimate_source_x);
                        end
                    end

                    if (emit_busy) begin
                        if (prefetch_count != 2'd0) begin
                            prefetch_count <= prefetch_count - 1'b1;
                        end else if (emit_count == EMIT_DIV - 1) begin
                            emit_count <= 8'd0;
                            output_valid <= 1'b1;
                            output_rgb <= active_output_pixel ?
                                (FILTER_ENABLE ? filtered_data : current_data) : 24'd0;
                            output_pixel_count <= output_pixel_count + 1'b1;

                            if (output_x == OUTPUT_WIDTH - 1) begin
                                output_y_remainder <= output_y_next;
                                // Stop the active image by row count.  The
                                // following idle-emit cycle performs the
                                // total-pixel/tail-border decision,
                                // keeping that counter out of the horizontal
                                // Bresenham register-enable path.
                                if (active_rows_remaining <= 16'd1) begin
                                    active_rows_remaining <= 16'd0;
                                    emit_busy <= 1'b0;
                                end else if (rows_left > 3'd1) begin
                                    active_rows_remaining <=
                                        active_rows_remaining - 16'd1;
                                    rows_left <= rows_left - 1'b1;
                                    output_x <= 16'd0;
                                    source_x <= 16'd0;
                                    horizontal_accumulator <= 16'd0;
                                    source_x_step_precalc <= 3'd0;
                                    horizontal_remainder_precalc <= 16'd0;
                                    read_address <= crop_x_start_address;
                                    read_address_right <= crop_x_start_address + 1'b1;
                                    prefetch_count <= 2'd2;
                                end else begin
                                    active_rows_remaining <=
                                        active_rows_remaining - 16'd1;
                                    emit_busy <= 1'b0;
                                end
                            end else begin
                                output_x <= output_x + 1'b1;
                                if (active_output_pixel &&
                                    !last_active_output_pixel) begin
                                    source_x <= source_x + source_x_step_precalc;
                                    horizontal_accumulator <=
                                        horizontal_remainder_precalc;
                                    read_address <= next_read_address;
                                    read_address_right <= next_read_address_right;
                                end
                            end
                        end else begin
                            emit_count <= emit_count + 1'b1;
                        end
                    end else if (source_all_seen) begin
                        if (output_pixel_count < FRAME_PIXELS) begin
                            black_pixels_remaining <=
                                FRAME_PIXELS - output_pixel_count;
                            emit_count <= 8'd0;
                            phase <= PH_TAIL_BORDER;
                        end else begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PH_IDLE;
                        end
                    end
                end

                PH_TAIL_BORDER: begin
                    if (emit_count == EMIT_DIV - 1) begin
                        emit_count <= 8'd0;
                        output_valid <= 1'b1;
                        output_rgb <= 24'd0;
                        output_pixel_count <= output_pixel_count + 1'b1;
                        if ((black_pixels_remaining <= 1) ||
                            (output_pixel_count >= LAST_FRAME_PIXEL)) begin
                            black_pixels_remaining <= {PIXEL_COUNT_BITS{1'b0}};
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PH_IDLE;
                        end else begin
                            black_pixels_remaining <=
                                black_pixels_remaining - 1'b1;
                        end
                    end else begin
                        emit_count <= emit_count + 1'b1;
                    end
                end

                default: begin
                    busy <= 1'b0;
                    phase <= PH_IDLE;
                end
            endcase
        end
    end
end

endmodule
