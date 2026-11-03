`timescale 1ns/1ps

module fat32_file_reader #(
    parameter integer SD_PROGRESS_TIMEOUT_CYCLES = 50_000_000,
    parameter integer MAX_CHAIN_CLUSTERS = 8192
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sd_init_done,

    input  wire        start,
    input  wire        stop,
    input  wire        allow_next_sector,
    input  wire [31:0] first_cluster,
    input  wire [31:0] file_size,
    input  wire [31:0] start_offset,
    input  wire [31:0] read_length,
    input  wire [7:0]  sectors_per_cluster,
    input  wire [2:0]  sectors_per_cluster_shift,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [31:0] max_cluster,

    output wire        busy,
    output reg         done,
    output reg         sector_done,
    output reg         data_valid,
    output reg  [7:0]  data_byte,
    output reg  [31:0] data_offset,
    output reg  [7:0]  error_code,

    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,
    output reg         sd_recover_pulse
);

localparam [7:0] ERR_NONE             = 8'h00;
localparam [7:0] ERR_SECTOR           = 8'h10;
localparam [7:0] ERR_ARGUMENT         = 8'h27;
localparam [7:0] ERR_CHAIN_LOOP       = 8'h23;
localparam [7:0] ERR_CLUSTER_RANGE    = 8'h24;
localparam [7:0] ERR_EARLY_EOF        = 8'h25;
localparam [7:0] ERR_CHAIN_EXHAUSTED  = 8'h26;
localparam [7:0] ERR_MISSING_EOF      = 8'h28;

localparam [3:0] ST_IDLE       = 4'd0;
localparam [3:0] ST_PREPARE    = 4'd1;
localparam [3:0] ST_SKIP_FAT_REQ = 4'd2;
localparam [3:0] ST_FAT_WAIT   = 4'd3;
localparam [3:0] ST_FAT_PARSE  = 4'd4;
localparam [3:0] ST_DATA_PREP  = 4'd5;
localparam [3:0] ST_DATA_REQ   = 4'd6;
localparam [3:0] ST_DATA_WAIT  = 4'd7;
localparam [3:0] ST_FINISH     = 4'd8;
localparam [3:0] ST_FAT_REQ    = 4'd9;
localparam [3:0] ST_STOP_WAIT  = 4'd10;
localparam [3:0] ST_FAT_PREP   = 4'd11;
localparam [3:0] ST_FAT_ADDR_HI = 4'd12;
localparam [3:0] ST_DATA_NEXT   = 4'd13;
localparam [4:0] ST_DATA_SHIFT = 5'd14;
localparam [4:0] ST_DATA_ADDR  = 5'd15;
localparam [4:0] ST_FAT_SETTLE = 5'd16;
localparam [4:0] ST_CHECK_REQUEST = 5'd17;
localparam [4:0] ST_FAT_CHECK = 5'd18;

localparam [1:0] FAT_REASON_SKIP = 2'd0;
localparam [1:0] FAT_REASON_NEXT = 2'd1;
localparam [1:0] FAT_REASON_EOF  = 2'd2;

reg [4:0] state;
reg [1:0] fat_reason;
reg [31:0] current_cluster;
reg [31:0] skip_cluster_count;
reg [7:0] sector_in_cluster;
reg [8:0] initial_byte_skip;
reg [31:0] remaining_bytes;
reg [31:0] visited_cluster_count;
reg [31:0] current_data_offset;
reg request_arguments_invalid;
reg request_reaches_file_end;
reg [31:0] request_bytes_available;
reg request_start_past_end;
reg [31:0] request_max_cluster;
reg fat_addr_carry;
reg [31:0] cluster_sector_offset;
reg fat_is_eof;
reg fat_cluster_invalid;
reg fat_cluster_below_min;
reg fat_cluster_high_greater;
reg fat_cluster_high_equal;
reg fat_cluster_low_greater;
reg fat_is_self;
reg chain_limit_reached;

reg [9:0] sector_byte_count;
reg sector_almost_full;
reg sector_full;
reg sector_skip_complete;
localparam integer PROGRESS_COUNT_WIDTH = (SD_PROGRESS_TIMEOUT_CYCLES > 1) ?
                                         $clog2(SD_PROGRESS_TIMEOUT_CYCLES) : 1;
reg [PROGRESS_COUNT_WIDTH-1:0] progress_timeout_count;
reg timeout_due;
reg [8:0] fat_entry_offset;
reg [7:0] fat_byte0;
reg [7:0] fat_byte1;
reg [7:0] fat_byte2;
reg [7:0] fat_byte3;

wire read_wait_state;
wire progress_seen;
wire progress_timeout;
wire [10:0] sector_byte_count_after;
wire short_sector_end;
wire stream_byte_selected;
wire [27:0] parsed_fat_entry;
wire [31:0] parsed_fat_cluster;

assign busy = (state != ST_IDLE);
assign read_wait_state = (state == ST_FAT_WAIT) ||
                         (state == ST_DATA_WAIT) ||
                         (state == ST_STOP_WAIT);
assign progress_seen = sd_sec_read_data_valid || sd_sec_read_end;
assign progress_timeout = read_wait_state && !progress_seen &&
    (SD_PROGRESS_TIMEOUT_CYCLES > 0) &&
    ((SD_PROGRESS_TIMEOUT_CYCLES <= 1) || timeout_due);
assign sector_byte_count_after = sector_byte_count +
                                 (sd_sec_read_data_valid ? 11'd1 : 11'd0);
assign short_sector_end = read_wait_state && sd_sec_read_end &&
                          (sd_sec_read_data_valid ?
                           !sector_almost_full : !sector_full);
assign stream_byte_selected = (state == ST_DATA_WAIT) &&
                              sd_sec_read_data_valid &&
                              !stop &&
                              sector_skip_complete &&
                              (remaining_bytes != 32'd0);
assign parsed_fat_entry = {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0};
assign parsed_fat_cluster = {4'd0, parsed_fat_entry};

always @(posedge clk) begin
    fat_is_eof <= parsed_fat_entry >= 28'hffffff8;
    // Bound each comparison stage to 16 bits. The extra FAT check state
    // lets the last entry byte traverse both stages before it is consumed.
    fat_cluster_below_min <= parsed_fat_cluster < 32'd2;
    fat_cluster_high_greater <= parsed_fat_cluster[31:16] > max_cluster[31:16];
    fat_cluster_high_equal <= parsed_fat_cluster[31:16] == max_cluster[31:16];
    fat_cluster_low_greater <= parsed_fat_cluster[15:0] > max_cluster[15:0];
    fat_cluster_invalid <= fat_cluster_below_min || fat_cluster_high_greater ||
                           (fat_cluster_high_equal && fat_cluster_low_greater);
    fat_is_self <= parsed_fat_cluster == current_cluster;
    chain_limit_reached <= visited_cluster_count >= MAX_CHAIN_CLUSTERS;
end

always @(posedge clk or posedge rst) begin
    if (rst || !sd_init_done || !read_wait_state || progress_seen) begin
        progress_timeout_count <= 32'd0;
        timeout_due <= 1'b0;
    end else if (!progress_timeout) begin
        progress_timeout_count <= progress_timeout_count + 32'd1;
        timeout_due <= (progress_timeout_count >= SD_PROGRESS_TIMEOUT_CYCLES - 2);
    end
end

always @(posedge clk or posedge rst) begin
    if (rst || !sd_init_done)
        sector_skip_complete <= 1'b0;
    else if (state == ST_DATA_REQ)
        sector_skip_complete <= (initial_byte_skip == 9'd0);
    else if ((state == ST_DATA_WAIT) && sd_sec_read_data_valid &&
             !sector_skip_complete &&
             (sector_byte_count + 10'd1 == {1'b0, initial_byte_skip}))
        sector_skip_complete <= 1'b1;
end

always @(posedge clk or posedge rst) begin
    if (rst || !sd_init_done || !read_wait_state || sd_sec_read_end) begin
        sector_byte_count <= 10'd0;
        sector_almost_full <= 1'b0;
        sector_full <= 1'b0;
    end else if (sd_sec_read_data_valid) begin
        sector_byte_count <= sector_byte_count + 10'd1;
        sector_almost_full <= (sector_byte_count == 10'd510);
        sector_full <= (sector_byte_count == 10'd511);
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= ST_IDLE;
        fat_reason <= FAT_REASON_SKIP;
        current_cluster <= 32'd0;
        skip_cluster_count <= 32'd0;
        sector_in_cluster <= 8'd0;
        initial_byte_skip <= 9'd0;
        remaining_bytes <= 32'd0;
        visited_cluster_count <= 32'd0;
        current_data_offset <= 32'd0;
        request_arguments_invalid <= 1'b0;
        request_reaches_file_end <= 1'b0;
        request_bytes_available <= 32'd0;
        request_start_past_end <= 1'b0;
        request_max_cluster <= 32'd0;
        fat_addr_carry <= 1'b0;
        cluster_sector_offset <= 32'd0;
        done <= 1'b0;
        sector_done <= 1'b0;
        data_valid <= 1'b0;
        data_byte <= 8'd0;
        data_offset <= 32'd0;
        error_code <= ERR_NONE;
        sd_sec_read <= 1'b0;
        sd_sec_read_addr <= 32'd0;
        sd_recover_pulse <= 1'b0;
        fat_entry_offset <= 9'd0;
        fat_byte0 <= 8'd0;
        fat_byte1 <= 8'd0;
        fat_byte2 <= 8'd0;
        fat_byte3 <= 8'd0;
    end else if (!sd_init_done) begin
        state <= ST_IDLE;
        done <= 1'b0;
        sector_done <= 1'b0;
        data_valid <= 1'b0;
        sd_sec_read <= 1'b0;
        sd_recover_pulse <= 1'b0;
    end else begin
        done <= 1'b0;
        sector_done <= 1'b0;
        data_valid <= 1'b0;
        sd_recover_pulse <= 1'b0;

        if ((state == ST_FAT_WAIT) && sd_sec_read_data_valid) begin
            if (sector_byte_count == fat_entry_offset)
                fat_byte0 <= sd_sec_read_data;
            else if (sector_byte_count == fat_entry_offset + 9'd1)
                fat_byte1 <= sd_sec_read_data;
            else if (sector_byte_count == fat_entry_offset + 9'd2)
                fat_byte2 <= sd_sec_read_data;
            else if (sector_byte_count == fat_entry_offset + 9'd3)
                fat_byte3 <= sd_sec_read_data;
        end

        if (stream_byte_selected) begin
            data_valid <= 1'b1;
            data_byte <= sd_sec_read_data;
            data_offset <= current_data_offset;
            current_data_offset <= current_data_offset + 32'd1;
            remaining_bytes <= remaining_bytes - 32'd1;
        end

        if (stop && (state != ST_IDLE) && (state != ST_STOP_WAIT)) begin
            if (read_wait_state && !sd_sec_read_end) begin
                state <= ST_STOP_WAIT;
            end else begin
                sd_sec_read <= 1'b0;
                state <= ST_IDLE;
            end
        end else if (progress_timeout || short_sector_end) begin
            sd_sec_read <= 1'b0;
            sd_recover_pulse <= 1'b1;
            error_code <= ERR_SECTOR;
            state <= ST_FINISH;
        end else begin
            case (state)
                ST_IDLE: begin
                    sd_sec_read <= 1'b0;
                    if (start) begin
                        error_code <= ERR_NONE;
                        data_offset <= start_offset;
                        current_data_offset <= start_offset;
                        remaining_bytes <= read_length;
                        current_cluster <= first_cluster;
                        visited_cluster_count <= 32'd1;
                        request_bytes_available <= file_size - start_offset;
                        request_start_past_end <= start_offset > file_size;
                        request_max_cluster <= max_cluster;
                        state <= ST_CHECK_REQUEST;
                    end
                end

                ST_CHECK_REQUEST: begin
                    request_arguments_invalid <=
                        request_start_past_end ||
                        (remaining_bytes > request_bytes_available) ||
                        ((remaining_bytes != 32'd0) &&
                         ((current_cluster < 32'd2) ||
                          (current_cluster > request_max_cluster))) ||
                        (sectors_per_cluster == 8'd0);
                    request_reaches_file_end <=
                        !request_start_past_end &&
                        (remaining_bytes == request_bytes_available);
                    state <= ST_PREPARE;
                end

                ST_PREPARE: begin
                    if (request_arguments_invalid) begin
                        error_code <= ERR_ARGUMENT;
                        state <= ST_FINISH;
                    end else if (remaining_bytes == 32'd0) begin
                        state <= ST_FINISH;
                    end else begin
                        case (sectors_per_cluster_shift)
                            3'd0: skip_cluster_count <= current_data_offset >> 9;
                            3'd1: skip_cluster_count <= current_data_offset >> 10;
                            3'd2: skip_cluster_count <= current_data_offset >> 11;
                            3'd3: skip_cluster_count <= current_data_offset >> 12;
                            3'd4: skip_cluster_count <= current_data_offset >> 13;
                            3'd5: skip_cluster_count <= current_data_offset >> 14;
                            3'd6: skip_cluster_count <= current_data_offset >> 15;
                            default: skip_cluster_count <= current_data_offset >> 16;
                        endcase
                        sector_in_cluster <=
                            (current_data_offset >> 9) &
                            (sectors_per_cluster - 8'd1);
                        initial_byte_skip <= current_data_offset[8:0];
                        state <= ST_SKIP_FAT_REQ;
                    end
                end

                ST_SKIP_FAT_REQ: begin
                    if (skip_cluster_count == 32'd0) begin
                        state <= ST_DATA_PREP;
                    end else if (chain_limit_reached) begin
                        error_code <= ERR_CHAIN_EXHAUSTED;
                        state <= ST_FINISH;
                    end else begin
                        fat_reason <= FAT_REASON_SKIP;
                        state <= ST_FAT_PREP;
                    end
                end

                ST_FAT_PREP: begin
                    fat_entry_offset <= {current_cluster[6:0], 2'b00};
                    fat_byte0 <= 8'd0;
                    fat_byte1 <= 8'd0;
                    fat_byte2 <= 8'd0;
                    fat_byte3 <= 8'd0;
                    {fat_addr_carry, sd_sec_read_addr[15:0]} <=
                        {1'b0, fat_start_lba[15:0]} +
                        {1'b0, current_cluster[22:7]};
                    state <= ST_FAT_ADDR_HI;
                end

                ST_FAT_ADDR_HI: begin
                    sd_sec_read_addr[31:16] <= fat_start_lba[31:16] +
                        {7'd0, current_cluster[31:23]} + fat_addr_carry;
                    state <= ST_FAT_REQ;
                end

                ST_FAT_REQ: begin
                    sd_sec_read <= 1'b1;
                    state <= ST_FAT_WAIT;
                end

                ST_FAT_WAIT: if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    state <= ST_FAT_SETTLE;
                end

                ST_FAT_SETTLE: state <= ST_FAT_CHECK;

                ST_FAT_CHECK: state <= ST_FAT_PARSE;

                ST_FAT_PARSE: begin
                    if (fat_reason == FAT_REASON_EOF) begin
                        if (fat_is_eof) begin
                            state <= ST_FINISH;
                        end else if (fat_cluster_invalid) begin
                            error_code <= ERR_CLUSTER_RANGE;
                            state <= ST_FINISH;
                        end else begin
                            error_code <= ERR_MISSING_EOF;
                            state <= ST_FINISH;
                        end
                    end else if (fat_is_eof) begin
                        error_code <= ERR_EARLY_EOF;
                        state <= ST_FINISH;
                    end else if (fat_cluster_invalid) begin
                        error_code <= ERR_CLUSTER_RANGE;
                        state <= ST_FINISH;
                    end else if (fat_is_self) begin
                        error_code <= ERR_CHAIN_LOOP;
                        state <= ST_FINISH;
                    end else if (chain_limit_reached) begin
                        error_code <= ERR_CHAIN_EXHAUSTED;
                        state <= ST_FINISH;
                    end else begin
                        current_cluster <= parsed_fat_cluster;
                        visited_cluster_count <= visited_cluster_count + 32'd1;
                        if (fat_reason == FAT_REASON_SKIP) begin
                            skip_cluster_count <= skip_cluster_count - 32'd1;
                            state <= ST_SKIP_FAT_REQ;
                        end else begin
                            sector_in_cluster <= 8'd0;
                            initial_byte_skip <= 9'd0;
                            state <= ST_DATA_PREP;
                        end
                    end
                end

                ST_DATA_PREP: begin
                    cluster_sector_offset <= current_cluster - 32'd2;
                    state <= ST_DATA_SHIFT;
                end

                ST_DATA_SHIFT: begin
                    cluster_sector_offset <= cluster_sector_offset << sectors_per_cluster_shift;
                    state <= ST_DATA_ADDR;
                end

                ST_DATA_ADDR: begin
                    sd_sec_read_addr <= data_start_lba + cluster_sector_offset + sector_in_cluster;
                    state <= ST_DATA_REQ;
                end

                ST_DATA_REQ: if (allow_next_sector) begin
                    sd_sec_read <= 1'b1;
                    state <= ST_DATA_WAIT;
                end

                ST_DATA_WAIT: if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    sector_done <= 1'b1;
                    initial_byte_skip <= 9'd0;
                    if ((remaining_bytes == 32'd0) ||
                        (stream_byte_selected && (remaining_bytes == 32'd1))) begin
                        if (request_reaches_file_end) begin
                            fat_reason <= FAT_REASON_EOF;
                            state <= ST_FAT_PREP;
                        end else begin
                            state <= ST_FINISH;
                        end
                    end else begin
                        state <= ST_DATA_NEXT;
                    end
                end

                // Do not prefetch FAT while the consumer owns the completed
                // sector. Every chain error must belong to an active request.
                ST_DATA_NEXT: if (allow_next_sector) begin
                    if ((sector_in_cluster + 8'd1) <
                                 sectors_per_cluster) begin
                        sector_in_cluster <= sector_in_cluster + 8'd1;
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                        state <= ST_DATA_REQ;
                    end else begin
                        fat_reason <= FAT_REASON_NEXT;
                        state <= ST_FAT_PREP;
                    end
                end

                ST_FINISH: begin
                    sd_sec_read <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                ST_STOP_WAIT: if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    state <= ST_IDLE;
                end

                default: begin
                    error_code <= ERR_ARGUMENT;
                    state <= ST_FINISH;
                end
            endcase
        end
    end
end

endmodule
