`timescale 1ns/1ps

module fat32_volume_scanner #(
    parameter integer SD_PROGRESS_TIMEOUT_CYCLES = 50_000_000,
    parameter integer MAX_ROOT_CLUSTERS = 1024,
    // Optional 00.BMP uses spare virtual slot 12; course slots stay 0..11.
    parameter SEARCH_HOME = 1'b0
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        sd_init_done,

    output wire        busy,
    output reg         done,
    output reg  [7:0]  error_code,

    output reg  [7:0]  sectors_per_cluster,
    output reg  [2:0]  sectors_per_cluster_shift,
    output reg  [31:0] fat_start_lba,
    output reg  [31:0] data_start_lba,
    output reg  [31:0] max_cluster,

    output reg         file_found_valid,
    output reg  [3:0]  file_found_index,
    output reg  [31:0] file_found_cluster,
    output reg  [31:0] file_found_size,
    output reg  [11:0] file_found_mask,

    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,
    output reg         sd_recover_pulse
);

localparam [7:0] ERR_NONE             = 8'h00;
localparam [7:0] ERR_SECTOR           = 8'h10;
localparam [7:0] ERR_BOOT_SIGNATURE   = 8'h20;
localparam [7:0] ERR_UNSUPPORTED_BPB  = 8'h21;
localparam [7:0] ERR_FILE_MISSING     = 8'h22;
localparam [7:0] ERR_ROOT_CHAIN       = 8'h23;
localparam [7:0] ERR_CLUSTER_RANGE    = 8'h24;

localparam [4:0] ST_IDLE          = 5'd0;
localparam [4:0] ST_READ0_REQ     = 5'd1;
localparam [4:0] ST_READ0_WAIT    = 5'd2;
localparam [4:0] ST_BOOT_REQ      = 5'd3;
localparam [4:0] ST_BOOT_WAIT     = 5'd4;
localparam [4:0] ST_BOOT_PARSE    = 5'd5;
localparam [4:0] ST_LAYOUT        = 5'd6;
localparam [4:0] ST_ROOT_PREP     = 5'd7;
localparam [4:0] ST_ROOT_REQ      = 5'd8;
localparam [4:0] ST_ROOT_WAIT     = 5'd9;
localparam [4:0] ST_ROOT_FAT_REQ  = 5'd10;
localparam [4:0] ST_ROOT_FAT_WAIT = 5'd11;
localparam [4:0] ST_ROOT_FAT_PARSE= 5'd12;
localparam [4:0] ST_FINISH        = 5'd13;
localparam [4:0] ST_ROOT_CHECK    = 5'd14;
localparam [4:0] ST_READ0_CHECK   = 5'd15;
localparam [4:0] ST_BOOT_CHECK    = 5'd16;
localparam [4:0] ST_ROOT_END      = 5'd17;
localparam [4:0] ST_ROOT_SUB      = 5'd18;
localparam [4:0] ST_ROOT_SHIFT    = 5'd19;
localparam [4:0] ST_ROOT_ADDR     = 5'd20;
localparam [4:0] ST_LAYOUT_PREP   = 5'd21;
localparam [4:0] ST_ROOT_FAT_SETTLE = 5'd22;
localparam [4:0] ST_LAYOUT_CHECK  = 5'd23;
localparam [4:0] ST_ROOT_COMMIT   = 5'd24;
localparam [4:0] ST_ROOT_VALIDATE = 5'd25;
localparam [4:0] ST_ROOT_DRAIN    = 5'd26;

// Keep the physical end handshake on the request register only. All parser
// data/valid/end inputs cross the same one-cycle SD-domain register boundary.
// Clearing the request on raw end prevents a duplicate CMD17 while the parser
// consumes its delayed final byte/end; no controller or CDC protocol changes.
reg [7:0] raw_response_data /* fehdl keep="true" */;
reg raw_response_valid /* fehdl keep="true" */;
reg raw_response_end /* fehdl keep="true" */;
reg [7:0] parse_data /* fehdl keep="true" */;
reg parse_valid /* fehdl keep="true" */;
reg parse_end /* fehdl keep="true" */;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        raw_response_data <= 8'd0;
        raw_response_valid <= 1'b0;
        raw_response_end <= 1'b0;
        parse_data <= 8'd0;
        parse_valid <= 1'b0;
        parse_end <= 1'b0;
    end else if (!sd_init_done) begin
        raw_response_data <= 8'd0;
        raw_response_valid <= 1'b0;
        raw_response_end <= 1'b0;
        parse_data <= 8'd0;
        parse_valid <= 1'b0;
        parse_end <= 1'b0;
    end else begin
        raw_response_data <= sd_sec_read_data;
        raw_response_valid <= sd_sec_read_data_valid;
        raw_response_end <= sd_sec_read_end;
        parse_data <= raw_response_data;
        parse_valid <= raw_response_valid;
        parse_end <= raw_response_end;
    end
end

reg [4:0] state;
reg [9:0] sector_byte_count;
reg sector_almost_full;
reg sector_full;
localparam integer PROGRESS_COUNT_WIDTH = (SD_PROGRESS_TIMEOUT_CYCLES > 1) ?
                                         $clog2(SD_PROGRESS_TIMEOUT_CYCLES) : 1;
reg [PROGRESS_COUNT_WIDTH-1:0] progress_timeout_count;
reg timeout_due;

reg [7:0] jump0;
reg [7:0] signature0;
reg [7:0] signature1;
reg partition_type_is_fat32;
reg partition_found;
reg [31:0] partition_candidate_lba;
reg [31:0] mbr_partition_lba;
reg [31:0] partition_lba;

reg [15:0] bpb_bytes_per_sector;
reg [7:0]  bpb_sectors_per_cluster;
reg [15:0] bpb_reserved_sectors;
reg [7:0]  bpb_fat_count;
reg [15:0] bpb_root_entry_count;
reg [15:0] bpb_total_sectors16;
reg [15:0] bpb_fat_sectors16;
reg [31:0] bpb_total_sectors32;
reg [31:0] bpb_fat_sectors32;
reg [15:0] bpb_ext_flags;
reg [31:0] bpb_root_cluster;
reg [31:0] total_sectors;
reg [31:0] fat_sectors;
reg [31:0] all_fat_sectors;
reg [31:0] data_sector_count;
reg [31:0] data_cluster_count;
reg [31:0] fat_entry_capacity;
reg [31:0] root_cluster;
reg [7:0]  active_fat_index;
reg [31:0] root_sector_offset;
reg [31:0] root_sector_base;
reg [31:0] volume_overhead;
reg layout_invalid;
reg [31:0] first_fat_lba;
reg bpb_invalid;
reg superfloppy_bpb;
reg fat_is_eof;
reg fat_cluster_invalid;
reg fat_is_self;
reg root_layout_invalid;
reg root_cluster_invalid;
reg root_more_sectors;
reg root_chain_limit_reached;

reg [7:0] dir_name0;
reg [7:0] dir_name1;
reg       dir_name_match;
reg [7:0] dir_attr;
reg [15:0] dir_cluster_high;
reg [15:0] dir_cluster_low;
reg [31:0] dir_file_size;
reg        dir_end_seen;
reg [7:0]  root_sector_index;
reg [15:0] root_cluster_count;

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
wire [27:0] parsed_fat_entry;
wire [31:0] parsed_fat_cluster;
wire [3:0] matched_file_index;
wire [31:0] completed_dir_file_size;
wire [31:0] completed_dir_cluster;
reg directory_candidate_valid;
reg directory_candidate_accept;
reg [3:0] directory_candidate_index;
reg [31:0] directory_candidate_cluster;
reg [31:0] directory_candidate_size;
reg dir_cluster_high_less;
reg dir_cluster_high_equal;
reg dir_cluster_low_within;
reg dir_cluster_at_least_two;
reg home_found;

assign busy = (state != ST_IDLE);
assign read_wait_state = (state == ST_READ0_WAIT) ||
                         (state == ST_BOOT_WAIT) ||
                         (state == ST_ROOT_WAIT) ||
                         (state == ST_ROOT_FAT_WAIT);
assign progress_seen = parse_valid || parse_end;
assign progress_timeout = read_wait_state && !progress_seen &&
    (SD_PROGRESS_TIMEOUT_CYCLES > 0) &&
    ((SD_PROGRESS_TIMEOUT_CYCLES <= 1) || timeout_due);
assign sector_byte_count_after = sector_byte_count +
                                 (parse_valid ? 11'd1 : 11'd0);
assign short_sector_end = read_wait_state && parse_end &&
                          (parse_valid ?
                           !sector_almost_full : !sector_full);
assign parsed_fat_entry = {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0};
assign parsed_fat_cluster = {4'd0, parsed_fat_entry};
assign completed_dir_file_size = {parse_data, dir_file_size[23:0]};
assign completed_dir_cluster = {dir_cluster_high, dir_cluster_low};
assign matched_file_index = ((dir_name0 == "0") && (dir_name1 == "0")) ?
                            4'd12 : (dir_name0 == "0") ?
                            (dir_name1 - "1") :
                            (4'd9 + (dir_name1 - "0"));

// The controller spends only one cycle in READ_END. Drop the request at
// that raw handshake, before its next WAIT cycle, then hold it low through
// delayed parsing/check/commit states. Only explicit REQ states can raise it.
always @(posedge clk or posedge rst) begin
    if (rst)
        sd_sec_read <= 1'b0;
    else if (!sd_init_done || sd_sec_read_end || progress_timeout || short_sector_end)
        sd_sec_read <= 1'b0;
    else if ((state == ST_READ0_REQ) || (state == ST_BOOT_REQ) ||
             (state == ST_ROOT_REQ) || (state == ST_ROOT_FAT_REQ))
        sd_sec_read <= 1'b1;
    else if (!read_wait_state)
        sd_sec_read <= 1'b0;
end

function [2:0] cluster_shift;
    input [7:0] value;
    begin
        case (value)
            8'd1:   cluster_shift = 3'd0;
            8'd2:   cluster_shift = 3'd1;
            8'd4:   cluster_shift = 3'd2;
            8'd8:   cluster_shift = 3'd3;
            8'd16:  cluster_shift = 3'd4;
            8'd32:  cluster_shift = 3'd5;
            8'd64:  cluster_shift = 3'd6;
            default: cluster_shift = 3'd7;
        endcase
    end
endfunction

function valid_cluster_size;
    input [7:0] value;
    begin
        valid_cluster_size = (value == 8'd1) || (value == 8'd2) ||
                             (value == 8'd4) || (value == 8'd8) ||
                             (value == 8'd16) || (value == 8'd32) ||
                             (value == 8'd64) || (value == 8'd128);
    end
endfunction

function fat32_partition_type;
    input [7:0] value;
    begin
        fat32_partition_type = (value == 8'h0b) || (value == 8'h0c);
    end
endfunction

// BPB fields settle long before the sector signature. Register the wide
// validation reductions instead of driving every state/address enable from
// the same combinational error decode.
always @(posedge clk) begin
    // Directory cluster bytes finish at offset 27, four byte clocks before
    // the candidate is captured at 31. Compare halves in parallel while
    // they settle; the accept cycle sees both halves from the same entry.
    // No control CE/reset mux belongs on these continuously sampled flags.
    dir_cluster_high_less <= dir_cluster_high < max_cluster[31:16];
    dir_cluster_high_equal <= dir_cluster_high == max_cluster[31:16];
    dir_cluster_low_within <= dir_cluster_low <= max_cluster[15:0];
    dir_cluster_at_least_two <= (dir_cluster_high != 16'd0) ||
                               (dir_cluster_low >= 16'd2);
    fat_is_eof <= parsed_fat_entry >= 28'hffffff8;
    fat_cluster_invalid <= (parsed_fat_cluster < 32'd2) ||
                           (parsed_fat_cluster > max_cluster);
    fat_is_self <= parsed_fat_cluster == root_cluster;
    superfloppy_bpb <= ((jump0 == 8'heb) || (jump0 == 8'he9)) &&
        (bpb_bytes_per_sector == 16'd512) &&
        valid_cluster_size(bpb_sectors_per_cluster) &&
        (bpb_root_entry_count == 16'd0) &&
        (bpb_fat_sectors16 == 16'd0) && (bpb_fat_sectors32 != 32'd0);
    bpb_invalid <= (bpb_bytes_per_sector != 16'd512) ||
        !valid_cluster_size(bpb_sectors_per_cluster) ||
        (bpb_reserved_sectors == 16'd0) ||
        ((bpb_fat_count != 8'd1) && (bpb_fat_count != 8'd2)) ||
        (bpb_root_entry_count != 16'd0) ||
        (bpb_fat_sectors16 != 16'd0) || (bpb_fat_sectors32 == 32'd0) ||
        ((bpb_total_sectors16 == 16'd0) && (bpb_total_sectors32 == 32'd0)) ||
        (bpb_root_cluster < 32'd2) ||
        (bpb_ext_flags[7] && (bpb_ext_flags[3:0] >= bpb_fat_count));
end

// The index/count stay stable throughout a root sector transfer. Register
// the terminal decisions at request time to keep their arithmetic/compare
// chain off the end-of-sector error mux. No extra request cycle is needed.
// Update only for root requests; aborts and idle periods retain the flags.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        root_more_sectors <= 1'b0;
        root_chain_limit_reached <= 1'b0;
    end else if (sd_init_done && (state == ST_ROOT_REQ)) begin
        root_more_sectors <= ((root_sector_index + 8'd1) <
                              sectors_per_cluster);
        root_chain_limit_reached <=
            (root_cluster_count >= MAX_ROOT_CLUSTERS - 1);
    end
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

// Sector parser registers are deliberately kept outside the control FSM.
// Every consumed field is overwritten by a complete 512-byte sector before
// use; short sectors abort the transaction.  Avoiding control-FSM clears here
// removes a large mux/reset network from the 100 MHz SD domain.
always @(posedge clk) begin
    if (state == ST_READ0_REQ) begin
        partition_type_is_fat32 <= 1'b0;
        partition_found <= 1'b0;
        partition_candidate_lba <= 32'd0;
        mbr_partition_lba <= 32'd0;
    end

    if ((state == ST_ROOT_CHECK) ||
        (state == ST_ROOT_FAT_PARSE &&
         !fat_is_eof && !fat_cluster_invalid && !fat_is_self))
        dir_end_seen <= 1'b0;

    if (parse_valid) begin
        if ((state == ST_READ0_WAIT) || (state == ST_BOOT_WAIT)) begin
            case (sector_byte_count)
                10'd0: jump0 <= parse_data;
                10'd11: bpb_bytes_per_sector[7:0] <= parse_data;
                10'd12: bpb_bytes_per_sector[15:8] <= parse_data;
                10'd13: bpb_sectors_per_cluster <= parse_data;
                10'd14: bpb_reserved_sectors[7:0] <= parse_data;
                10'd15: bpb_reserved_sectors[15:8] <= parse_data;
                10'd16: bpb_fat_count <= parse_data;
                10'd17: bpb_root_entry_count[7:0] <= parse_data;
                10'd18: bpb_root_entry_count[15:8] <= parse_data;
                10'd19: bpb_total_sectors16[7:0] <= parse_data;
                10'd20: bpb_total_sectors16[15:8] <= parse_data;
                10'd22: bpb_fat_sectors16[7:0] <= parse_data;
                10'd23: bpb_fat_sectors16[15:8] <= parse_data;
                10'd32: bpb_total_sectors32[7:0] <= parse_data;
                10'd33: bpb_total_sectors32[15:8] <= parse_data;
                10'd34: bpb_total_sectors32[23:16] <= parse_data;
                10'd35: bpb_total_sectors32[31:24] <= parse_data;
                10'd36: bpb_fat_sectors32[7:0] <= parse_data;
                10'd37: bpb_fat_sectors32[15:8] <= parse_data;
                10'd38: bpb_fat_sectors32[23:16] <= parse_data;
                10'd39: bpb_fat_sectors32[31:24] <= parse_data;
                10'd40: bpb_ext_flags[7:0] <= parse_data;
                10'd41: bpb_ext_flags[15:8] <= parse_data;
                10'd44: bpb_root_cluster[7:0] <= parse_data;
                10'd45: bpb_root_cluster[15:8] <= parse_data;
                10'd46: bpb_root_cluster[23:16] <= parse_data;
                10'd47: bpb_root_cluster[31:24] <= parse_data;
                10'd450, 10'd466, 10'd482, 10'd498: begin
                    partition_type_is_fat32 <=
                        fat32_partition_type(parse_data);
                    partition_candidate_lba <= 32'd0;
                end
                10'd454, 10'd470, 10'd486, 10'd502:
                    partition_candidate_lba[7:0] <= parse_data;
                10'd455, 10'd471, 10'd487, 10'd503:
                    partition_candidate_lba[15:8] <= parse_data;
                10'd456, 10'd472, 10'd488, 10'd504:
                    partition_candidate_lba[23:16] <= parse_data;
                10'd457, 10'd473, 10'd489, 10'd505: begin
                    partition_candidate_lba[31:24] <= parse_data;
                    if (partition_type_is_fat32 && !partition_found) begin
                        mbr_partition_lba <=
                            {parse_data, partition_candidate_lba[23:0]};
                        partition_found <= 1'b1;
                    end
                end
                10'd510: signature0 <= parse_data;
                10'd511: signature1 <= parse_data;
                default: ;
            endcase
        end else if (state == ST_ROOT_WAIT) begin
            case (sector_byte_count[4:0])
                5'd0: begin
                    dir_name0 <= parse_data;
                    dir_name_match <= (parse_data == "0") ||
                                      (parse_data == "1");
                    if (parse_data == 8'h00)
                        dir_end_seen <= 1'b1;
                end
                5'd1: begin
                    dir_name1 <= parse_data;
                    dir_name_match <= dir_name_match &&
                        (((dir_name0 == "0") &&
                          (parse_data >= (SEARCH_HOME ? "0" : "1")) &&
                          (parse_data <= "9")) ||
                         ((dir_name0 == "1") &&
                          (parse_data >= "0") &&
                          (parse_data <= "2")));
                end
                5'd2, 5'd3, 5'd4, 5'd5, 5'd6, 5'd7:
                    dir_name_match <= dir_name_match &&
                                      (parse_data == " ");
                5'd8: dir_name_match <= dir_name_match &&
                                              (parse_data == "B");
                5'd9: dir_name_match <= dir_name_match &&
                                              (parse_data == "M");
                5'd10: dir_name_match <= dir_name_match &&
                                               (parse_data == "P");
                5'd11: dir_attr <= parse_data;
                5'd20: dir_cluster_high[7:0] <= parse_data;
                5'd21: dir_cluster_high[15:8] <= parse_data;
                5'd26: dir_cluster_low[7:0] <= parse_data;
                5'd27: dir_cluster_low[15:8] <= parse_data;
                5'd28: dir_file_size[7:0] <= parse_data;
                5'd29: dir_file_size[15:8] <= parse_data;
                5'd30: dir_file_size[23:16] <= parse_data;
                5'd31: dir_file_size[31:24] <= parse_data;
                default: ;
            endcase
        end else if (state == ST_ROOT_FAT_WAIT) begin
            if (sector_byte_count == fat_entry_offset)
                fat_byte0 <= parse_data;
            else if (sector_byte_count == fat_entry_offset + 9'd1)
                fat_byte1 <= parse_data;
            else if (sector_byte_count == fat_entry_offset + 9'd2)
                fat_byte2 <= parse_data;
            else if (sector_byte_count == fat_entry_offset + 9'd3)
                fat_byte3 <= parse_data;
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst || !sd_init_done || !read_wait_state || parse_end) begin
        sector_byte_count <= 10'd0;
        sector_almost_full <= 1'b0;
        sector_full <= 1'b0;
    end else if (parse_valid) begin
        sector_byte_count <= sector_byte_count + 10'd1;
        sector_almost_full <= (sector_byte_count == 10'd510);
        sector_full <= (sector_byte_count == 10'd511);
    end
end

always @(posedge clk or posedge rst) begin
    if (rst || !sd_init_done) begin
        root_sector_base <= 32'd0;
        root_sector_offset <= 32'd0;
    end else begin
        if (state == ST_ROOT_SUB)
            root_sector_base <= root_cluster - 32'd2;
        if (state == ST_ROOT_SHIFT)
            root_sector_offset <= root_sector_base << sectors_per_cluster_shift;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= ST_IDLE;
        done <= 1'b0;
        error_code <= ERR_NONE;
        sectors_per_cluster <= 8'd0;
        sectors_per_cluster_shift <= 3'd0;
        fat_start_lba <= 32'd0;
        data_start_lba <= 32'd0;
        max_cluster <= 32'd0;
        file_found_valid <= 1'b0;
        file_found_index <= 4'd0;
        file_found_cluster <= 32'd0;
        file_found_size <= 32'd0;
        file_found_mask <= 12'd0;
        home_found <= 1'b0;
        directory_candidate_valid <= 1'b0;
        directory_candidate_accept <= 1'b0;
        directory_candidate_index <= 4'd0;
        directory_candidate_cluster <= 32'd0;
        directory_candidate_size <= 32'd0;
        sd_sec_read_addr <= 32'd0;
        sd_recover_pulse <= 1'b0;
        partition_lba <= 32'd0;
        total_sectors <= 32'd0;
        fat_sectors <= 32'd0;
        all_fat_sectors <= 32'd0;
        data_sector_count <= 32'd0;
        data_cluster_count <= 32'd0;
        fat_entry_capacity <= 32'd0;
        root_cluster <= 32'd0;
        active_fat_index <= 8'd0;
        volume_overhead <= 32'd0;
        layout_invalid <= 1'b0;
        root_layout_invalid <= 1'b0;
        root_cluster_invalid <= 1'b0;
        first_fat_lba <= 32'd0;
        root_sector_index <= 8'd0;
        root_cluster_count <= 16'd0;
        fat_entry_offset <= 9'd0;
    end else if (!sd_init_done) begin
        state <= ST_IDLE;
        done <= 1'b0;
        file_found_valid <= 1'b0;
        directory_candidate_valid <= 1'b0;
        directory_candidate_accept <= 1'b0;
        sd_recover_pulse <= 1'b0;
    end else begin
        done <= 1'b0;
        file_found_valid <= 1'b0;
        sd_recover_pulse <= 1'b0;

        directory_candidate_valid <= (state == ST_ROOT_WAIT) &&
            parse_valid && (sector_byte_count[4:0] == 5'd31) &&
            !dir_end_seen && dir_name_match && (dir_attr != 8'h0f) &&
            ((dir_attr & 8'h18) == 8'h00);
        // A final-byte/end handshake leaves the last candidate pending in
        // COMMIT. Validate it there, then publish it in DRAIN before END
        // examines file_found_mask or advances to the next cluster.
        directory_candidate_accept <=
            ((state == ST_ROOT_WAIT) || (state == ST_ROOT_COMMIT)) &&
            !progress_timeout && !short_sector_end &&
            directory_candidate_valid &&
            dir_cluster_at_least_two &&
            (dir_cluster_high_less ||
             (dir_cluster_high_equal && dir_cluster_low_within)) &&
            (directory_candidate_size != 32'd0) &&
            ((directory_candidate_index == 4'd12) ? !home_found :
             !file_found_mask[directory_candidate_index]);
        if ((state == ST_ROOT_WAIT) && parse_valid &&
            (sector_byte_count[4:0] == 5'd31)) begin
            directory_candidate_index <= matched_file_index;
            directory_candidate_cluster <= completed_dir_cluster;
            directory_candidate_size <= completed_dir_file_size;
        end
        if (directory_candidate_accept && !progress_timeout &&
            !short_sector_end &&
            ((state == ST_ROOT_WAIT) || (state == ST_ROOT_COMMIT) ||
             (state == ST_ROOT_DRAIN))) begin
            file_found_valid <= 1'b1;
            file_found_index <= directory_candidate_index;
            file_found_cluster <= directory_candidate_cluster;
            file_found_size <= directory_candidate_size;
            if (directory_candidate_index == 4'd12)
                home_found <= 1'b1;
            else
                file_found_mask[directory_candidate_index] <= 1'b1;
        end

        if (progress_timeout || short_sector_end) begin
            sd_recover_pulse <= 1'b1;
            error_code <= ERR_SECTOR;
            state <= ST_FINISH;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        error_code <= ERR_NONE;
                        file_found_mask <= 12'd0;
                        home_found <= 1'b0;
                        partition_lba <= 32'd0;
                        root_cluster_count <= 16'd0;
                        state <= ST_READ0_REQ;
                    end
                end

                ST_READ0_REQ: begin
                    partition_lba <= 32'd0;
                    sd_sec_read_addr <= 32'd0;
                    state <= ST_READ0_WAIT;
                end

                ST_READ0_WAIT: if (parse_end) begin
                    state <= ST_READ0_CHECK;
                end

                ST_READ0_CHECK: begin
                    if ((signature0 != 8'h55) || (signature1 != 8'haa)) begin
                        error_code <= ERR_BOOT_SIGNATURE;
                        state <= ST_FINISH;
                    end else if (superfloppy_bpb) begin
                        partition_lba <= 32'd0;
                        state <= ST_BOOT_PARSE;
                    end else if (partition_found) begin
                        partition_lba <= mbr_partition_lba;
                        sd_sec_read_addr <= mbr_partition_lba;
                        state <= ST_BOOT_REQ;
                    end else begin
                        error_code <= ERR_UNSUPPORTED_BPB;
                        state <= ST_FINISH;
                    end
                end

                ST_BOOT_REQ: begin
                    state <= ST_BOOT_WAIT;
                end

                ST_BOOT_WAIT: if (parse_end) begin
                    state <= ST_BOOT_CHECK;
                end

                ST_BOOT_CHECK: begin
                    if ((signature0 != 8'h55) || (signature1 != 8'haa)) begin
                        error_code <= ERR_BOOT_SIGNATURE;
                        state <= ST_FINISH;
                    end else begin
                        state <= ST_BOOT_PARSE;
                    end
                end

                ST_BOOT_PARSE: begin
                    if (bpb_invalid) begin
                        error_code <= ERR_UNSUPPORTED_BPB;
                        state <= ST_FINISH;
                    end else begin
                        sectors_per_cluster <= bpb_sectors_per_cluster;
                        sectors_per_cluster_shift <=
                            cluster_shift(bpb_sectors_per_cluster);
                        total_sectors <= (bpb_total_sectors16 != 16'd0) ?
                                         {16'd0, bpb_total_sectors16} :
                                         bpb_total_sectors32;
                        fat_sectors <= bpb_fat_sectors32;
                        all_fat_sectors <= (bpb_fat_count == 8'd2) ?
                                           (bpb_fat_sectors32 << 1) :
                                           bpb_fat_sectors32;
                        active_fat_index <= bpb_ext_flags[7] ?
                                            {4'd0, bpb_ext_flags[3:0]} : 8'd0;
                        root_cluster <= bpb_root_cluster;
                        state <= ST_LAYOUT_PREP;
                    end
                end

                ST_LAYOUT_PREP: begin
                    first_fat_lba <= partition_lba + bpb_reserved_sectors;
                    volume_overhead <= {16'd0, bpb_reserved_sectors} + all_fat_sectors;
                    state <= ST_LAYOUT;
                end

                ST_LAYOUT: begin
                    fat_start_lba <= first_fat_lba +
                                     ((active_fat_index == 8'd0) ?
                                      32'd0 : fat_sectors);
                    data_start_lba <= partition_lba + volume_overhead;
                    layout_invalid <= (total_sectors <= volume_overhead);
                    data_sector_count <= total_sectors - volume_overhead;
                    state <= ST_LAYOUT_CHECK;
                end

                ST_LAYOUT_CHECK: begin
                    if (layout_invalid) begin
                        error_code <= ERR_UNSUPPORTED_BPB;
                        state <= ST_FINISH;
                    end else begin
                        state <= ST_ROOT_PREP;
                    end
                end

                ST_ROOT_PREP: begin
                    data_cluster_count <= data_sector_count >>
                                          sectors_per_cluster_shift;
                    max_cluster <= (data_sector_count >>
                                    sectors_per_cluster_shift) + 32'd1;
                    fat_entry_capacity <= fat_sectors << 7;
                    state <= ST_ROOT_VALIDATE;
                end

                // The layout registers above must settle before validation.
                // Keep wide comparisons off the directory-control CE path.
                ST_ROOT_VALIDATE: begin
                    root_layout_invalid <= (max_cluster >= fat_entry_capacity) ||
                        (data_cluster_count >= 32'h0fff_fff5);
                    root_cluster_invalid <= (root_cluster < 32'd2) ||
                                            (root_cluster > max_cluster);
                    state <= ST_ROOT_CHECK;
                end

                ST_ROOT_CHECK: begin
                    if (root_layout_invalid) begin
                        error_code <= ERR_UNSUPPORTED_BPB;
                        state <= ST_FINISH;
                    end else if (root_cluster_invalid) begin
                        error_code <= ERR_CLUSTER_RANGE;
                        state <= ST_FINISH;
                    end else begin
                        root_sector_index <= 8'd0;
                        state <= ST_ROOT_SUB;
                    end
                end

                ST_ROOT_REQ: begin
                    state <= ST_ROOT_WAIT;
                end

                ST_ROOT_WAIT: if (parse_end) begin
                    state <= ST_ROOT_COMMIT;
                end

                ST_ROOT_COMMIT: state <= ST_ROOT_DRAIN;
                ST_ROOT_DRAIN: state <= ST_ROOT_END;

                ST_ROOT_END: begin
                    if ((file_found_mask == 12'hfff) &&
                        (!SEARCH_HOME || home_found)) begin
                        state <= ST_FINISH;
                    end else if (dir_end_seen) begin
                        error_code <= (file_found_mask == 12'hfff) ?
                                      ERR_NONE : ERR_FILE_MISSING;
                        state <= ST_FINISH;
                    end else if (root_more_sectors) begin
                        root_sector_index <= root_sector_index + 8'd1;
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                        state <= ST_ROOT_REQ;
                    end else if (root_chain_limit_reached) begin
                        error_code <= ERR_ROOT_CHAIN;
                        state <= ST_FINISH;
                    end else begin
                        fat_entry_offset <= {root_cluster[6:0], 2'b00};
                        sd_sec_read_addr <= fat_start_lba +
                                            (root_cluster >> 7);
                        state <= ST_ROOT_FAT_REQ;
                    end
                end

                ST_ROOT_FAT_REQ: begin
                    state <= ST_ROOT_FAT_WAIT;
                end

                ST_ROOT_FAT_WAIT: if (parse_end) begin
                    state <= ST_ROOT_FAT_SETTLE;
                end

                ST_ROOT_FAT_SETTLE: state <= ST_ROOT_FAT_PARSE;

                ST_ROOT_FAT_PARSE: begin
                    if (fat_is_eof) begin
                        error_code <= (file_found_mask == 12'hfff) ?
                                      ERR_NONE : ERR_FILE_MISSING;
                        state <= ST_FINISH;
                    end else if (fat_cluster_invalid) begin
                        error_code <= ERR_CLUSTER_RANGE;
                        state <= ST_FINISH;
                    end else if (fat_is_self) begin
                        error_code <= ERR_ROOT_CHAIN;
                        state <= ST_FINISH;
                    end else begin
                        root_cluster <= parsed_fat_cluster;
                        root_cluster_count <= root_cluster_count + 16'd1;
                        root_sector_index <= 8'd0;
                        state <= ST_ROOT_SUB;
                    end
                end

                ST_ROOT_SUB: state <= ST_ROOT_SHIFT;

                ST_ROOT_SHIFT: state <= ST_ROOT_ADDR;

                ST_ROOT_ADDR: begin
                    sd_sec_read_addr <= data_start_lba + root_sector_offset;
                    state <= ST_ROOT_REQ;
                end

                ST_FINISH: begin
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    error_code <= ERR_UNSUPPORTED_BPB;
                    state <= ST_FINISH;
                end
            endcase
        end
    end
end

endmodule
