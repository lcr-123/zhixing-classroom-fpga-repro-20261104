`timescale 1ns/1ps

module thumbnail_capture_bram #(
    parameter integer SOURCE_WIDTH = 640,
    parameter integer SOURCE_HEIGHT = 480,
    parameter integer SAMPLE_SHIFT = 3,
    parameter integer THUMB_WIDTH = 80,
    parameter integer THUMB_HEIGHT = 60,
    parameter integer PIXELS = THUMB_WIDTH * THUMB_HEIGHT,
    parameter integer ADDR_WIDTH = 13
) (
    input  wire                  pixel_clk,
    input  wire                  pixel_rst,
    input  wire                  video_user,
    input  wire                  video_valid,
    input  wire [23:0]           video_rgb,
    input  wire                  request_toggle,
    output reg                   done_toggle,
    output reg  [15:0]           frame_id,
    output reg  [31:0]           frame_crc32,
    input  wire                  read_clk,
    input  wire [ADDR_WIDTH-1:0] read_addr,
    output reg  [15:0]           read_data
);

function [31:0] crc32_byte;
    input [31:0] crc;
    input [7:0] data;
    integer bit_index;
    reg [31:0] value;
    begin
        value = crc ^ data;
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            if (value[0])
                value = (value >> 1) ^ 32'hEDB88320;
            else
                value = value >> 1;
        end
        crc32_byte = value;
    end
endfunction

// Keep the thumbnail store in explicit BRAM banks. 4800x16 is represented by
// five 1024x16 logical banks (each bank may use two native 512x18 blocks).
// Compared with ten 512-word banks this halves the bank-select/mux fanout while
// preserving the same BRAM capacity and one-read-clock latency.
localparam integer BANK_ADDR_WIDTH = (ADDR_WIDTH < 10) ? ADDR_WIDTH : 10;
localparam integer BANK_DEPTH = 1 << BANK_ADDR_WIDTH;
localparam integer BANK_COUNT = (PIXELS + BANK_DEPTH - 1) / BANK_DEPTH;
localparam integer BANK_SELECT_WIDTH = (BANK_COUNT > 1) ? $clog2(BANK_COUNT) : 1;
wire [BANK_COUNT*16-1:0] bank_read_data;
reg [BANK_SELECT_WIDTH-1:0] read_bank;
reg read_in_range;
reg request_meta;
reg request_sync;
reg request_seen;
reg capture_pending;
reg capture_active;
reg [10:0] source_x;
reg [9:0] source_y;
reg [ADDR_WIDTH-1:0] write_addr;
reg memory_write_en;
reg [ADDR_WIDTH-1:0] memory_write_addr;
reg [15:0] memory_write_data;
reg [31:0] crc32_value;

wire [15:0] rgb565 = {
    video_rgb[23:19], video_rgb[15:10], video_rgb[7:3]
};
wire [31:0] crc_after_low = crc32_byte(crc32_value, rgb565[7:0]);
wire [31:0] crc_after_high = crc32_byte(crc_after_low, rgb565[15:8]);

genvar bank;
generate
    for (bank = 0; bank < BANK_COUNT; bank = bank + 1) begin : g_bank
        reg [15:0] memory [0:BANK_DEPTH-1] /* fehdl force_ram=1, ram_style="bram" */;
        reg [15:0] data;
        always @(posedge pixel_clk)
            if (memory_write_en && ((memory_write_addr >> BANK_ADDR_WIDTH) == bank))
                memory[memory_write_addr[BANK_ADDR_WIDTH-1:0]] <= memory_write_data;
        always @(posedge read_clk)
            if ((read_addr < PIXELS) && ((read_addr >> BANK_ADDR_WIDTH) == bank))
                data <= memory[read_addr[BANK_ADDR_WIDTH-1:0]];
        assign bank_read_data[bank*16 +: 16] = data;
    end
endgenerate

always @(posedge read_clk) begin
    read_bank <= read_addr >> BANK_ADDR_WIDTH;
    read_in_range <= read_addr < PIXELS;
end

integer read_index;
always @(*) begin
    read_data = 16'd0;
    for (read_index = 0; read_index < BANK_COUNT; read_index = read_index + 1)
        if (read_in_range && (read_bank == read_index))
            read_data = bank_read_data[read_index*16 +: 16];
end

// The request originates on the related 50 MHz clock. Its falling-edge
// capture avoids a same-edge hold path before the normal synchronizer stage.
always @(negedge pixel_clk or posedge pixel_rst) begin
    if (pixel_rst)
        request_meta <= 1'b0;
    else
        request_meta <= request_toggle;
end

always @(posedge pixel_clk or posedge pixel_rst) begin
    if (pixel_rst) begin
        request_sync    <= 1'b0;
        request_seen    <= 1'b0;
        capture_pending <= 1'b0;
        capture_active  <= 1'b0;
        done_toggle     <= 1'b0;
        frame_id        <= 16'd0;
        frame_crc32     <= 32'd0;
        source_x        <= 11'd0;
        source_y        <= 10'd0;
        write_addr      <= {ADDR_WIDTH{1'b0}};
        memory_write_en <= 1'b0;
        memory_write_addr <= {ADDR_WIDTH{1'b0}};
        memory_write_data <= 16'd0;
        crc32_value     <= 32'hFFFFFFFF;
    end else begin
        memory_write_en <= 1'b0;
        request_sync <= request_meta;

        if (request_sync != request_seen) begin
            request_seen    <= request_sync;
            capture_pending <= 1'b1;
        end

        if (!capture_active) begin
            source_x <= 11'd0;
            source_y <= 10'd0;
            if (capture_pending && video_user && video_valid) begin
                capture_pending <= 1'b0;
                capture_active  <= 1'b1;
                memory_write_en   <= 1'b1;
                memory_write_addr <= {ADDR_WIDTH{1'b0}};
                memory_write_data <= rgb565;
                write_addr      <= {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                crc32_value     <= crc_after_high;
                source_x        <= 11'd1;
            end
        end else if (video_valid) begin
            if ((source_x[SAMPLE_SHIFT-1:0] == 0) &&
                (source_y[SAMPLE_SHIFT-1:0] == 0)) begin
                memory_write_en     <= 1'b1;
                memory_write_addr   <= write_addr;
                memory_write_data   <= rgb565;
                write_addr         <= write_addr + 1'b1;
                crc32_value        <= crc_after_high;
                if (write_addr == PIXELS - 1) begin
                    capture_active <= 1'b0;
                    frame_id       <= frame_id + 1'b1;
                    frame_crc32    <= ~crc_after_high;
                    // Preserve the just-computed result in frame_crc32, then
                    // prepare an independent CRC32 stream for the next request.
                    crc32_value    <= 32'hFFFFFFFF;
                    done_toggle    <= ~done_toggle;
                end
            end

            if (source_x == SOURCE_WIDTH - 1) begin
                source_x <= 11'd0;
                if (source_y == SOURCE_HEIGHT - 1)
                    source_y <= 10'd0;
                else
                    source_y <= source_y + 1'b1;
            end else begin
                source_x <= source_x + 1'b1;
            end
        end
    end
end

endmodule
