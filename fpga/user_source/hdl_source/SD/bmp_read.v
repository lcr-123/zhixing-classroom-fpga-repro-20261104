module bmp_read #(
    parameter integer SD_PROGRESS_TIMEOUT_CYCLES = 50_000_000,
    parameter integer CROP_READ_ENABLE = 0
)(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [3:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [3:0]            scan_found_total,
    output reg                  scan_found_voice,
    output reg [31:0]           scan_found_voice_offset,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,
    output reg                  load_error_pulse,
    output reg                  sd_recover_pulse,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output [15:0]               source_width,
    output [15:0]               source_height,

    output reg                  write_req,
    input                       write_req_ack,
    input                       source_start,
    input  [15:0]               source_first_row,
    input  [15:0]               source_roi_rows,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,
    input                       sd_sec_read_error,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA = 3'd4;
localparam ST_SOURCE_WAIT = 3'd5;
localparam ST_SEEK_ROWS = 3'd6;
localparam ST_SEEK_DONE = 3'd7;

reg [2:0]  state;
reg [9:0]  rd_cnt;
reg        header_byte_valid;
reg [9:0]  header_byte_index;
reg [7:0]  header_byte_data;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] dib_header_size;
reg [31:0] width;
reg [31:0] height;
reg [15:0] color_planes;
reg [15:0] bit_count;
reg [31:0] compression;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [31:0] pixel_start_prior;
reg [31:0] pixel_end_prior;
reg pixel_region_active;
reg [1:0]  bmp_byte_idx;
reg [17:0] row_byte_pos;
reg [17:0] row_last_byte_pos;
reg [17:0] row_data_last_byte_pos;
reg        row_data_active;
reg [15:0] source_rows_remaining;
reg [31:0] required_file_end_registered;
reg [31:0] size_mul_accumulator;
reg [31:0] size_mul_multiplicand;
reg [15:0] size_mul_multiplier;
reg [4:0]  size_mul_count;
reg        size_mul_active;
reg        size_mul_start_pulse;
reg [1:0] size_mul_mode;
reg [15:0] roi_first_row, roi_row_count;
reg [31:0] roi_start_byte, roi_end_byte;
reg roi_seek_done;
reg roi_bounds_checked;
reg roi_end_exceeds_file;
reg roi_end_not_after_start;
reg [31:0] roi_start_sector;
reg [31:0] roi_counter_origin;
wire crop_source_start = CROP_READ_ENABLE &&
                         (state == ST_SOURCE_WAIT) && source_start;
wire [31:0] load_region_end = CROP_READ_ENABLE ? roi_end_byte : required_file_end_registered;
reg        load_error_latched;
localparam integer PROGRESS_COUNT_WIDTH = (SD_PROGRESS_TIMEOUT_CYCLES > 1) ?
                                         $clog2(SD_PROGRESS_TIMEOUT_CYCLES) : 1;
reg [PROGRESS_COUNT_WIDTH-1:0] sd_progress_timeout_count;
reg sd_timeout_due;
reg [9:0]  sector_byte_count;

wire header_format_match;
wire header_file_match;
reg  header_format_stage;
reg  header_file_stage;
reg  header_match_registered;
reg [31:0] file_sector_count_registered;
wire bmp_data_valid;
wire [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;
reg [17:0] row_data_bytes;
reg [17:0] row_stride_bytes;
wire [17:0] row_data_bytes_next;
wire        voice_trailer_present;
wire        sd_read_state;
wire        sd_progress_seen;
wire        sd_progress_timeout;
wire        short_sector_end;

assign ready = (state == ST_IDLE);
// Split the wide BMP qualification into independent registered stages. The
// header fields are stable long before the sector end, so this adds no SD
// latency while keeping the final state transition to a short two-input AND.
assign header_format_match = (header_0 == "B") &&
                             (header_1 == "M") &&
                             (dib_header_size >= 32'd40) &&
                             (pixel_offset >= 32'd54) &&
                             (width[31:16] == 16'd0) &&
                             (width[15:0] != 16'd0) &&
                             (height[31:16] == 16'd0) &&
                             (height[15:0] != 16'd0) &&
                             (width[15:0] >= (bmp_width >> 1)) &&
                             (width[15:0] <= (bmp_width << 1)) &&
                             (height[15:0] >= (bmp_height >> 1)) &&
                             (height[15:0] <= (bmp_height << 1)) &&
                             (color_planes == 16'd1) &&
                             (bit_count    == 16'd24) &&
                             (compression  == 32'd0);
assign header_file_match = (file_len > pixel_offset) &&
                           (file_len >= required_file_end_registered);
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        pixel_region_active &&
                        (source_rows_remaining != 16'd0) &&
                        row_data_active;
assign file_sector_count = (file_len == 32'd0) ? 32'd1 : ((file_len + 32'd511) >> 9);
assign next_scan_sector_if_match = scan_sector + file_sector_count_registered;
assign next_scan_sector_if_miss  = scan_sector + 32'd1;
assign row_data_bytes_next = {2'b00, width[15:0]} +
                             {2'b00, width[15:0]} +
                             {2'b00, width[15:0]};
assign voice_trailer_present =
    (file_len >= (required_file_end_registered + 32'd16));
assign source_width = width[15:0];
assign source_height = height[15:0];
assign sd_read_state = (state == ST_SCAN) ||
                       (state == ST_LOAD_HDR) ||
                       (state == ST_LOAD_DATA);
assign sd_progress_seen = sd_sec_read_data_valid || sd_sec_read_end;
assign sd_progress_timeout = sd_read_state && !sd_progress_seen &&
    (SD_PROGRESS_TIMEOUT_CYCLES > 0) &&
    ((SD_PROGRESS_TIMEOUT_CYCLES <= 1) || sd_timeout_due);
assign short_sector_end = sd_read_state && sd_sec_read_end &&
                          (sector_byte_count != 10'd512);

// The lower SD controller can otherwise wait forever for a response token
// after a card/contact failure.  Count only intervals with no byte or sector
// progress, so normal full-frame transfers never approach this watchdog.
always @(posedge clk or posedge rst) begin
    if (rst || !sd_init_done || !sd_read_state || sd_progress_seen) begin
        sd_progress_timeout_count <= 32'd0;
        sd_timeout_due <= 1'b0;
    end else if (!sd_progress_timeout) begin
        sd_progress_timeout_count <= sd_progress_timeout_count + 32'd1;
        sd_timeout_due <= (sd_progress_timeout_count >= SD_PROGRESS_TIMEOUT_CYCLES - 2);
    end
end

// Every successful CMD17 must deliver exactly 512 data bytes.  Detecting a
// short sector here prevents stale header bytes or a shifted pixel stream from
// being accepted as a complete BMP.
always @(posedge clk or posedge rst) begin
    if (rst || !sd_init_done || !sd_read_state || sd_sec_read_end) begin
        sector_byte_count <= 10'd0;
    end else if (sd_sec_read_data_valid) begin
        sector_byte_count <= sector_byte_count + 10'd1;
    end
end

// Validate that the declared file can contain every padded source row before
// requesting an SDRAM frame write.  A 16-cycle shift/add calculation avoids
// consuming a DSP or creating a wide 100 MHz multiply path.  Header fields are
// stable hundreds of cycles before the first sector ends, so no I/O latency is
// added.
always @(posedge clk) begin
    if (rst)
        size_mul_start_pulse <= 1'b0;
    else
        size_mul_start_pulse <=
            ((state == ST_SCAN) || (state == ST_LOAD_HDR)) &&
            sd_sec_read_data_valid && (rd_cnt == 10'd33);
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        required_file_end_registered <= 32'd0;
        size_mul_accumulator <= 32'd0;
        size_mul_multiplicand <= 32'd0;
        size_mul_multiplier <= 16'd0;
        size_mul_count <= 5'd0;
        size_mul_active <= 1'b0;
        size_mul_mode <= 0;
        roi_first_row <= 0; roi_row_count <= 0;
        roi_start_byte <= 0; roi_end_byte <= 0;
        roi_seek_done <= 0;
    end else if (crop_source_start) begin
        roi_first_row <= source_first_row;
        roi_row_count <= source_roi_rows;
        roi_seek_done <= 0;
        size_mul_accumulator <= 0;
        size_mul_multiplicand <= {16'd0,row_stride_bytes[15:0]};
        size_mul_multiplier <= source_first_row;
        size_mul_count <= 0;
        size_mul_mode <= 1;
        size_mul_active <= 1;
    end else if (size_mul_start_pulse) begin
        size_mul_accumulator <= 32'd0;
        size_mul_multiplicand <= {16'd0, row_stride_bytes[15:0]};
        size_mul_multiplier <= height[15:0];
        size_mul_count <= 5'd0;
        size_mul_active <= 1'b1;
        size_mul_mode <= 0;
    end else if (size_mul_active) begin
        if (size_mul_multiplier[0])
            size_mul_accumulator <= size_mul_accumulator + size_mul_multiplicand;
        size_mul_multiplicand <= size_mul_multiplicand << 1;
        size_mul_multiplier <= size_mul_multiplier >> 1;

        if (size_mul_count == 5'd15) begin
            if (size_mul_mode == 0) begin
                required_file_end_registered <= pixel_offset +
                    size_mul_accumulator +
                    (size_mul_multiplier[0] ? size_mul_multiplicand : 32'd0);
                size_mul_active <= 0;
            end else if (size_mul_mode == 1) begin
                roi_start_byte <= pixel_offset + size_mul_accumulator +
                    (size_mul_multiplier[0] ? size_mul_multiplicand : 32'd0);
                size_mul_accumulator <= 0;
                size_mul_multiplicand <= {16'd0,row_stride_bytes[15:0]};
                size_mul_multiplier <= roi_row_count;
                size_mul_count <= 0;
                size_mul_mode <= 2;
            end else begin
                roi_end_byte <= roi_start_byte + size_mul_accumulator +
                    (size_mul_multiplier[0] ? size_mul_multiplicand : 32'd0);
                roi_seek_done <= 1;
                size_mul_active <= 0;
            end
        end else begin
            size_mul_count <= size_mul_count + 1'b1;
        end
    end
end

// The ROI arithmetic finishes before the read request. Register its wide
// bounds checks so the error-state transition does not include the comparators.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        roi_bounds_checked <= 1'b0;
        roi_end_exceeds_file <= 1'b0;
        roi_end_not_after_start <= 1'b0;
    end else if (crop_source_start || !sd_init_done) begin
        roi_bounds_checked <= 1'b0;
    end else begin
        roi_bounds_checked <= roi_seek_done;
        roi_end_exceeds_file <= roi_end_byte > required_file_end_registered;
        roi_end_not_after_start <= roi_end_byte <= roi_start_byte;
    end
end

// These seek results settle long before ST_SEEK_DONE. Keep the wide base
// addition and byte alignment out of the SD request address register CE.
always @(posedge clk) begin
    roi_start_sector <= load_sector_latched + (roi_start_byte >> 9);
    roi_counter_origin <= {roi_start_byte[31:9],9'd0};
end

// Header fields finish by byte 33, long before the 512-byte sector ends.
// Register both the comparison and rounded file length so the sector-end state
// transition does not combine a 32-bit round/add/compare chain in one cycle.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_format_stage <= 1'b0;
        header_file_stage <= 1'b0;
        header_match_registered <= 1'b0;
        file_sector_count_registered <= 32'd1;
    end else begin
        header_format_stage <= header_format_match;
        header_file_stage <= header_file_match;
        header_match_registered <= header_format_stage && header_file_stage;
        file_sector_count_registered <= file_sector_count;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_byte_valid <= 1'b0;
        header_byte_index <= 10'd0;
        header_byte_data <= 8'd0;
    end else begin
        header_byte_valid <= ((state == ST_SCAN) || (state == ST_LOAD_HDR)) &&
                             sd_sec_read_data_valid;
        header_byte_index <= rd_cnt;
        header_byte_data <= sd_sec_read_data;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        dib_header_size <= 32'd0;
        width        <= 32'd0;
        height       <= 32'd0;
        color_planes <= 16'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
    end else if (header_byte_valid) begin
        case (header_byte_index)
            10'd0 : header_0 <= header_byte_data;
            10'd1 : header_1 <= header_byte_data;

            10'd2 : file_len[7:0] <= header_byte_data;
            10'd3 : file_len[15:8] <= header_byte_data;
            10'd4 : file_len[23:16] <= header_byte_data;
            10'd5 : file_len[31:24] <= header_byte_data;

            10'd10: pixel_offset[7:0] <= header_byte_data;
            10'd11: pixel_offset[15:8] <= header_byte_data;
            10'd12: pixel_offset[23:16] <= header_byte_data;
            10'd13: pixel_offset[31:24] <= header_byte_data;

            10'd14: dib_header_size[7:0] <= header_byte_data;
            10'd15: dib_header_size[15:8] <= header_byte_data;
            10'd16: dib_header_size[23:16] <= header_byte_data;
            10'd17: dib_header_size[31:24] <= header_byte_data;

            10'd18: width[7:0] <= header_byte_data;
            10'd19: width[15:8] <= header_byte_data;
            10'd20: width[23:16] <= header_byte_data;
            10'd21: width[31:24] <= header_byte_data;

            10'd22: height[7:0] <= header_byte_data;
            10'd23: height[15:8] <= header_byte_data;
            10'd24: height[23:16] <= header_byte_data;
            10'd25: height[31:24] <= header_byte_data;

            10'd26: color_planes[7:0] <= header_byte_data;
            10'd27: color_planes[15:8] <= header_byte_data;

            10'd28: bit_count[7:0] <= header_byte_data;
            10'd29: bit_count[15:8] <= header_byte_data;

            10'd30: compression[7:0] <= header_byte_data;
            10'd31: compression[15:8] <= header_byte_data;
            10'd32: compression[23:16] <= header_byte_data;
            10'd33: compression[31:24] <= header_byte_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (CROP_READ_ENABLE && state == ST_SEEK_DONE) begin
        bmp_len_cnt <= roi_counter_origin;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        pixel_start_prior <= 32'd0;
        pixel_end_prior <= 32'd0;
        pixel_region_active <= 1'b0;
    end else if (CROP_READ_ENABLE && state == ST_SEEK_DONE) begin
        pixel_start_prior <= roi_start_byte - 32'd1;
        pixel_end_prior <= roi_end_byte - 32'd1;
        pixel_region_active <= (roi_start_byte[8:0] == 9'd0);
    end else if (state == ST_SOURCE_WAIT) begin
        pixel_start_prior <= pixel_offset - 32'd1;
        pixel_end_prior <= file_len - 32'd1;
        pixel_region_active <= 1'b0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid) begin
            if (bmp_len_cnt == pixel_start_prior)
                pixel_region_active <= 1'b1;
            if (bmp_len_cnt == pixel_end_prior)
                pixel_region_active <= 1'b0;
        end
    end else begin
        pixel_region_active <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        row_data_bytes <= 18'd0;
        row_stride_bytes <= 18'd0;
        row_data_last_byte_pos <= 18'd0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR)) &&
                 sd_sec_read_data_valid && (rd_cnt == 10'd26)) begin
        row_data_bytes <= row_data_bytes_next;
        row_stride_bytes <= (row_data_bytes_next + 18'd3) & 18'h3FFFC;
        row_data_last_byte_pos <= row_data_bytes_next - 18'd1;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst)
        row_data_active <= 1'b0;
    else if (state == ST_SOURCE_WAIT || (CROP_READ_ENABLE && state == ST_SEEK_DONE))
        row_data_active <= (row_data_bytes != 18'd0);
    else if (state == ST_LOAD_DATA && sd_sec_read_data_valid &&
             pixel_region_active) begin
        if (row_byte_pos == row_last_byte_pos)
            row_data_active <= (row_data_bytes != 18'd0);
        else if (row_byte_pos == row_data_last_byte_pos)
            row_data_active <= 1'b0;
    end else if (state != ST_LOAD_DATA)
        row_data_active <= 1'b0;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        row_byte_pos <= 18'd0;
        row_last_byte_pos <= 18'd0;
        source_rows_remaining <= 16'd0;
    end else if (state == ST_SOURCE_WAIT || (CROP_READ_ENABLE && state == ST_SEEK_DONE)) begin
        row_byte_pos <= 18'd0;
        row_last_byte_pos <= row_stride_bytes - 18'd1;
        source_rows_remaining <= CROP_READ_ENABLE && state == ST_SEEK_DONE ?
                                 roi_row_count : ((height[31:16] == 16'd0) ?
                                 height[15:0] : 16'd0);
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid &&
            pixel_region_active &&
            (source_rows_remaining != 16'd0)) begin
            if (row_byte_pos == row_last_byte_pos) begin
                row_byte_pos <= 18'd0;
                source_rows_remaining <= source_rows_remaining - 1'b1;
            end else begin
                row_byte_pos <= row_byte_pos + 1'b1;
            end
        end
    end else begin
        row_byte_pos <= 18'd0;
        source_rows_remaining <= 16'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx <= 2'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid)
            bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end else begin
        bmp_byte_idx <= 2'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data;
                end
                default: begin
                    bmp_data_wr_en <= 1'b0;
                end
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 4'd0;
        scan_found_voice  <= 1'b0;
        scan_found_voice_offset <= 32'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        load_error_pulse  <= 1'b0;
        sd_recover_pulse  <= 1'b0;
        load_error_latched <= 1'b0;
    end else if (!sd_init_done) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 4'd0;
        scan_found_voice  <= 1'b0;
        scan_found_voice_offset <= 32'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        load_error_pulse  <= 1'b0;
        sd_recover_pulse  <= 1'b0;
        load_error_latched <= 1'b0;
    end else begin
        scan_found_valid <= 1'b0;
        scan_found_voice <= 1'b0;
        load_error_pulse <= 1'b0;
        sd_recover_pulse <= 1'b0;

        if (sd_progress_timeout || short_sector_end || sd_sec_read_error) begin
            // Abort the current transaction and ask sd_card_top to restart the
            // complete command/SPI stack.  The parent keeps the last committed
            // display buffer, so a media fault cannot expose a half frame.
            state               <= ST_IDLE;
            state_code          <= 4'hE;
            sd_sec_read         <= 1'b0;
            write_req           <= 1'b0;
            load_error_pulse    <= 1'b1;
            load_error_latched  <= 1'b1;
            sd_recover_pulse    <= 1'b1;
        end else case (state)
            ST_IDLE: begin
                state_code  <= load_error_latched ? 4'hE : 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_found_total <= 4'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    load_error_latched  <= 1'b0;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;

                    if (header_match_registered) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 4'd1;
                        scan_found_voice  <= voice_trailer_present;
                        scan_found_voice_offset <=
                            required_file_end_registered;

                        if ((scan_found_total + 4'd1 >= scan_target_count) || (next_scan_sector_if_match > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end
                    end else begin
                        if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                        end
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match_registered) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        load_error_pulse   <= 1'b1;
                        load_error_latched <= 1'b1;
                        state_code         <= 4'hE;
                        state              <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack) begin
                    write_req <= 1'b0;
                    state     <= ST_SOURCE_WAIT;
                end
            end

            // The SDRAM writer has acknowledged and released its FIFO reset.
            // Wait here while the scaler emits any leading black border, then
            // reread the BMP from its first sector and begin the pixel stream.
            ST_SOURCE_WAIT: begin
                state_code  <= 4'd3;
                sd_sec_read <= 1'b0;
                if (source_start) begin
                    if (CROP_READ_ENABLE) begin
                        state <= ST_SEEK_ROWS;
                    end else begin
                        sd_sec_read_addr <= load_sector_latched;
                        state <= ST_LOAD_DATA;
                    end
                end
            end

            ST_SEEK_ROWS: begin
                sd_sec_read <= 0;
                // Source bounds come from the same scaler configuration
                // that consumes this stream. Refuse invalid ranges before
                // reading or publishing any pixel from them.
                if (roi_bounds_checked) begin
                    if (roi_row_count == 0 || roi_first_row >= height[15:0] ||
                        roi_end_exceeds_file || roi_end_not_after_start) begin
                        load_error_pulse <= 1;
                        load_error_latched <= 1;
                        state <= ST_IDLE;
                    end else state <= ST_SEEK_DONE;
                end
            end

            ST_SEEK_DONE: begin
                sd_sec_read_addr <= roi_start_sector;
                state <= ST_LOAD_DATA;
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    // Advance the sector address independently of the final
                    // pixel qualification.  The extra increment on the last
                    // sector is harmless because the next load re-latches
                    // load_sector_latched; keeping it unconditional removes
                    // the wide bmp_len_cnt/required_file_end compare from
                    // the address-register CE path.
                    sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    // The learning-card format may legally append an LMV1
                    // narration trailer after the padded pixel array.  Image
                    // loading stops after the sector containing the complete
                    // pixel array; the independent voice reader fetches the
                    // trailer later.  The scanner still skips the full
                    // declared file length, so embedded audio is never
                    // mistaken for another BMP.
                    if (bmp_len_cnt >= load_region_end) begin
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_LOAD_DATA;
                    end
                end
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule
