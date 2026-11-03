`timescale 1ns/1ps

module fat32_virtual_sector_bridge #(
    parameter integer SD_PROGRESS_TIMEOUT_CYCLES = 50_000_000,
    parameter integer MAX_CHAIN_CLUSTERS = 8192
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sd_init_done,

    input  wire        metadata_clear,
    input  wire        metadata_valid,
    input  wire [3:0]  metadata_index,
    input  wire [31:0] metadata_cluster,
    input  wire [31:0] metadata_size,
    output reg  [12:0] metadata_mask,

    input  wire [7:0]  sectors_per_cluster,
    input  wire [2:0]  sectors_per_cluster_shift,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [31:0] max_cluster,

    input  wire        virtual_read,
    input  wire [31:0] virtual_read_addr,
    output reg  [7:0]  virtual_read_data,
    output reg         virtual_read_data_valid,
    output reg         virtual_read_end,
    output reg         virtual_read_error,

    output wire        physical_read,
    output wire [31:0] physical_read_addr,
    input  wire [7:0]  physical_read_data,
    input  wire        physical_read_data_valid,
    input  wire        physical_read_end,
    output wire        sd_recover_pulse
);

localparam [3:0] ST_IDLE       = 4'd0;
localparam [3:0] ST_START      = 4'd1;
localparam [3:0] ST_STREAM     = 4'd2;
localparam [3:0] ST_PAD        = 4'd3;
localparam [3:0] ST_END        = 4'd4;
localparam [3:0] ST_WAIT_NEXT  = 4'd5;
localparam [3:0] ST_STOP       = 4'd6;
localparam [3:0] ST_ERROR      = 4'd7;
localparam [3:0] ST_WAIT_RELEASE = 4'd8;
localparam [3:0] ST_LOOKUP     = 4'd9;
localparam [3:0] ST_NEXT_CHECK = 4'd10;
localparam [3:0] ST_CAPTURE    = 4'd11;
localparam [3:0] ST_VALIDATE   = 4'd12;
localparam [3:0] ST_NEXT_PREP  = 4'd13;
localparam [3:0] ST_PAD_DRAIN  = 4'd14;

reg [3:0] state;
reg [63:0] file_metadata [0:15]
    /* fehdl force_ram=1, ram_style="bram" */;
reg [63:0] selected_file_metadata;
reg [3:0] metadata_read_index;
reg [9:0] output_count;
reg [31:0] active_virtual_addr;
reg [31:0] pending_virtual_addr;
reg pending_request;
reg active_last_sector;
reg reader_start;
reg reader_stop;
reg reader_allow_next_sector;
reg sequential_request;
reg [31:0] request_file_cluster_reg;
reg [31:0] request_file_size_reg;
reg [31:0] request_start_offset_reg;
reg [31:0] request_read_length_reg;
reg request_address_valid_reg;
reg request_last_sector_reg;

wire reader_busy;
wire reader_done;
wire reader_sector_done;
wire reader_data_valid;
wire [7:0] reader_data_byte;
wire [31:0] reader_data_offset;
wire [7:0] reader_error;
wire request_address_valid;
wire [3:0] request_file_index;
wire [19:0] request_sector_offset;
wire [31:0] request_byte_offset;
wire [31:0] selected_file_cluster;
wire [31:0] selected_file_size;
wire request_metadata_valid;
wire request_is_last_sector;
wire [10:0] output_count_after;

assign request_file_index = pending_virtual_addr[23:20];
assign request_sector_offset = pending_virtual_addr[19:0];
assign request_byte_offset = {request_sector_offset, 9'd0};
assign selected_file_cluster = selected_file_metadata[63:32];
assign selected_file_size = selected_file_metadata[31:0];
assign request_metadata_valid = (request_file_index < 4'd13) ?
                                metadata_mask[request_file_index] : 1'b0;
assign request_address_valid =
    (pending_virtual_addr[31:24] == 8'h80) &&
    (request_file_index < 4'd13) &&
    request_metadata_valid &&
    (request_start_offset_reg < request_file_size_reg);
assign request_is_last_sector =
    (request_start_offset_reg + 32'd512) >= request_file_size_reg;
assign output_count_after = output_count +
                            (reader_data_valid ? 11'd1 : 11'd0);

fat32_file_reader #(
    .SD_PROGRESS_TIMEOUT_CYCLES(SD_PROGRESS_TIMEOUT_CYCLES),
    .MAX_CHAIN_CLUSTERS(MAX_CHAIN_CLUSTERS)
) u_file_reader (
    .clk(clk),
    .rst(rst),
    .sd_init_done(sd_init_done),
    .start(reader_start),
    .stop(reader_stop),
    .allow_next_sector(reader_allow_next_sector),
    .first_cluster(request_file_cluster_reg),
    .file_size(request_file_size_reg),
    .start_offset(request_start_offset_reg),
    .read_length(request_read_length_reg),
    .sectors_per_cluster(sectors_per_cluster),
    .sectors_per_cluster_shift(sectors_per_cluster_shift),
    .fat_start_lba(fat_start_lba),
    .data_start_lba(data_start_lba),
    .max_cluster(max_cluster),
    .busy(reader_busy),
    .done(reader_done),
    .sector_done(reader_sector_done),
    .data_valid(reader_data_valid),
    .data_byte(reader_data_byte),
    .data_offset(reader_data_offset),
    .error_code(reader_error),
    .sd_sec_read(physical_read),
    .sd_sec_read_addr(physical_read_addr),
    .sd_sec_read_data(physical_read_data),
    .sd_sec_read_data_valid(physical_read_data_valid),
    .sd_sec_read_end(physical_read_end),
    .sd_recover_pulse(sd_recover_pulse)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        metadata_mask <= 13'd0;
    end else begin
        if (metadata_clear)
            metadata_mask <= 13'd0;
        if (metadata_valid && (metadata_index < 4'd13)) begin
            metadata_mask[metadata_index] <= 1'b1;
        end
    end
end

always @(posedge clk) begin
    if (metadata_valid && (metadata_index < 4'd13))
        file_metadata[metadata_index] <= {metadata_cluster, metadata_size};

    selected_file_metadata <= file_metadata[metadata_read_index];
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= ST_IDLE;
        output_count <= 10'd0;
        active_virtual_addr <= 32'd0;
        pending_virtual_addr <= 32'd0;
        metadata_read_index <= 4'd0;
        pending_request <= 1'b0;
        active_last_sector <= 1'b0;
        reader_start <= 1'b0;
        reader_stop <= 1'b0;
        reader_allow_next_sector <= 1'b0;
        sequential_request <= 1'b0;
        request_file_cluster_reg <= 32'd0;
        request_file_size_reg <= 32'd0;
        request_start_offset_reg <= 32'd0;
        request_read_length_reg <= 32'd0;
        request_address_valid_reg <= 1'b0;
        request_last_sector_reg <= 1'b0;
        virtual_read_data <= 8'd0;
        virtual_read_data_valid <= 1'b0;
        virtual_read_end <= 1'b0;
        virtual_read_error <= 1'b0;
    end else if (!sd_init_done) begin
        state <= ST_IDLE;
        reader_start <= 1'b0;
        reader_stop <= 1'b0;
        reader_allow_next_sector <= 1'b0;
        virtual_read_data_valid <= 1'b0;
        virtual_read_end <= 1'b0;
        virtual_read_error <= 1'b0;
    end else begin
        reader_start <= 1'b0;
        reader_stop <= 1'b0;
        virtual_read_data_valid <= 1'b0;
        virtual_read_end <= 1'b0;
        virtual_read_error <= 1'b0;

        if ((state == ST_STREAM) && reader_data_valid &&
            (output_count < 10'd512)) begin
            virtual_read_data <= reader_data_byte;
            virtual_read_data_valid <= 1'b1;
            output_count <= output_count + 10'd1;
            reader_allow_next_sector <= 1'b0;
        end

        case (state)
            ST_IDLE: begin
                reader_allow_next_sector <= 1'b0;
                if (virtual_read) begin
                    pending_virtual_addr <= virtual_read_addr;
                    metadata_read_index <= virtual_read_addr[23:20];
                    pending_request <= 1'b1;
                    state <= ST_LOOKUP;
                end
            end

            ST_LOOKUP: state <= ST_CAPTURE;

            ST_CAPTURE: begin
                request_file_cluster_reg <= selected_file_cluster;
                request_file_size_reg <= selected_file_size;
                request_start_offset_reg <= request_byte_offset;
                state <= ST_VALIDATE;
            end

            ST_VALIDATE: begin
                request_address_valid_reg <= request_address_valid;
                request_last_sector_reg <= request_is_last_sector;
                request_read_length_reg <= request_file_size_reg -
                                           request_start_offset_reg;
                state <= ST_START;
            end

            ST_START: begin
                if (!request_address_valid_reg) begin
                    state <= ST_ERROR;
                end else if (!reader_busy) begin
                    active_virtual_addr <= pending_virtual_addr;
                    pending_request <= 1'b0;
                    output_count <= 10'd0;
                    active_last_sector <= request_last_sector_reg;
                    reader_allow_next_sector <= 1'b1;
                    reader_start <= 1'b1;
                    state <= ST_STREAM;
                end
            end

            ST_STREAM: begin
                if (reader_done && (reader_error != 8'd0)) begin
                    state <= ST_ERROR;
                end else if (reader_done) begin
                    state <= (output_count_after >= 11'd512) ?
                             ST_END : ST_PAD;
                end else if (reader_sector_done &&
                             (output_count_after >= 11'd512) &&
                             !active_last_sector) begin
                    state <= ST_END;
                end
            end

            ST_PAD: begin
                virtual_read_data <= 8'd0;
                virtual_read_data_valid <= 1'b1;
                output_count <= output_count + 10'd1;
                if (output_count == 10'd511)
                    state <= ST_PAD_DRAIN;
            end

            // sd_card_bmp registers data/valid once before the BMP parser,
            // while sector-end is direct. Let the last padded byte reach
            // the consumer before publishing completion (count must be 512).
            ST_PAD_DRAIN: state <= ST_END;

            ST_END: begin
                virtual_read_end <= 1'b1;
                state <= ST_WAIT_RELEASE;
            end

            ST_WAIT_RELEASE: begin
                if (!virtual_read) begin
                    state <= ST_WAIT_NEXT;
                end
            end

            ST_WAIT_NEXT: begin
                if (virtual_read) begin
                    pending_virtual_addr <= virtual_read_addr;
                    metadata_read_index <= virtual_read_addr[23:20];
                    pending_request <= 1'b1;
                    sequential_request <= virtual_read_addr == (active_virtual_addr + 32'd1);
                    state <= ST_NEXT_PREP;
                end
            end

            ST_NEXT_PREP: begin
                request_start_offset_reg <= request_byte_offset;
                request_last_sector_reg <=
                    (request_byte_offset + 32'd512) >= request_file_size_reg;
                state <= ST_NEXT_CHECK;
            end

            ST_NEXT_CHECK: begin
                if (sequential_request && reader_busy) begin
                    active_virtual_addr <= pending_virtual_addr;
                    pending_request <= 1'b0;
                    output_count <= 10'd0;
                    active_last_sector <= request_last_sector_reg;
                    reader_allow_next_sector <= 1'b1;
                    state <= ST_STREAM;
                end else begin
                    if (reader_busy) begin
                        reader_stop <= 1'b1;
                        state <= ST_STOP;
                    end else begin
                        state <= ST_LOOKUP;
                    end
                end
            end

            ST_STOP: begin
                reader_allow_next_sector <= 1'b0;
                if (!reader_busy)
                    state <= pending_request ? ST_LOOKUP : ST_IDLE;
            end

            ST_ERROR: begin
                reader_allow_next_sector <= 1'b0;
                pending_request <= 1'b0;
                virtual_read_error <= 1'b1;
                virtual_read_end <= 1'b1;
                if (reader_busy)
                    reader_stop <= 1'b1;
                state <= ST_WAIT_RELEASE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
