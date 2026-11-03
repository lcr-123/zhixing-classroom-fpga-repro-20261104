`timescale 1ns/1ps

module audio_waveform_overlay #(
    parameter integer FRAME_WIDTH  = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer WAVE_WIDTH   = 640,
    parameter integer WAVE_TOP     = 416,
    parameter integer WAVE_HEIGHT  = 32,
    parameter integer SNAPSHOT_FRAME_DIV = 4,
    parameter integer GATE_SAMPLE_READ = 1
)(
    input  wire        pixel_clk,
    input  wire        pixel_rst,
    input  wire        frame_boundary,
    input  wire        in_hs,
    input  wire        in_vs,
    input  wire        in_de,
    input  wire [23:0] in_rgb,
    input  wire        overlay_enable,
    input  wire [3:0]  theme_index,
    input  wire        audio_valid,
    input  wire [23:0] audio_sample,
    output reg         out_hs,
    output reg         out_vs,
    output reg         out_de,
    output reg  [23:0] out_rgb
);

reg [7:0] sample_memory [0:255] /* fehdl force_ram=1, ram_style="bram" */;
reg [7:0] sample_write_ptr;
reg [7:0] sample_read_base;
reg [7:0] snapshot_frame_count;
reg [7:0] sample_read_data;
reg [9:0] pixel_x;
reg [9:0] pixel_y;
reg       input_de_d;
reg [9:0] pixel_x_d;
reg [9:0] pixel_y_d;
reg       hs_d;
reg       vs_d;
reg       de_d;
reg [23:0] rgb_d;
reg       hs_q;
reg       vs_q;
reg       de_q;
reg [23:0] rgb_q;
reg       wave_region_q;
reg       bar_pixel_q;
reg [23:0] bar_color_q;
reg       frame_overlay_enable;
reg [3:0] frame_theme_index;
wire [7:0] sample_level =
    (!audio_sample[23] && audio_sample[22]) ? 8'h7F :
    ( audio_sample[23] && !audio_sample[22]) ? 8'h80 :
    audio_sample[22:15];
// Eight display pixels form one thin bar. Each bar reads a stable point from
// the 256-sample snapshot, leaving enough spacing to match the reference UI.
wire [6:0] fetch_bar_index = pixel_x[9:3];
wire [7:0] sample_offset = {fetch_bar_index, 1'b0} +
                           {1'b0, fetch_bar_index};
wire [7:0] sample_index = sample_read_base + sample_offset;
wire sample_read_enable = frame_overlay_enable && in_de &&
                          (pixel_x < WAVE_WIDTH) &&
                          (pixel_y >= WAVE_TOP) &&
                          (pixel_y < WAVE_TOP + WAVE_HEIGHT);
localparam [9:0] WAVE_CENTER_Y = WAVE_TOP + (WAVE_HEIGHT / 2);
localparam [4:0] BAR_MAX_HALF = (WAVE_HEIGHT / 2) - 2;
wire [7:0] sample_magnitude =
    (sample_read_data == 8'h80) ? 8'h7F :
    (sample_read_data[7] ? (~sample_read_data + 1'b1) : sample_read_data);
wire [4:0] raw_half_height = {1'b0, sample_magnitude[6:3]} + 5'd1;
wire [4:0] bar_half_height =
    (raw_half_height > BAR_MAX_HALF) ? BAR_MAX_HALF : raw_half_height;
wire [9:0] bar_top_y = WAVE_CENTER_Y - bar_half_height;
wire [9:0] bar_bottom_y = WAVE_CENTER_Y + bar_half_height;
wire wave_region = frame_overlay_enable &&
                   (pixel_x_d < WAVE_WIDTH) &&
                   (pixel_y_d >= WAVE_TOP) &&
                   (pixel_y_d < WAVE_TOP + WAVE_HEIGHT);
wire bar_body_x = (pixel_x_d[2:0] >= 3'd2) &&
                  (pixel_x_d[2:0] <= 3'd5);
wire bar_cap_x = (pixel_x_d[2:0] >= 3'd3) &&
                 (pixel_x_d[2:0] <= 3'd4);
wire bar_cap_y = (pixel_y_d == bar_top_y) ||
                 (pixel_y_d == bar_bottom_y);
wire bar_pixel = wave_region &&
                 (pixel_y_d >= bar_top_y) &&
                 (pixel_y_d <= bar_bottom_y) &&
                 (bar_cap_y ? bar_cap_x : bar_body_x);
wire [23:0] panel_rgb = {
    1'b0, rgb_q[23:17],
    1'b0, rgb_q[15:9],
    1'b0, rgb_q[7:1]
};

function [1:0] theme_family;
    input [3:0] index;
    begin
        case (index)
            // Only the three narrated lesson cards have themed palettes.
            4'd0: theme_family = 2'd0;
            4'd1: theme_family = 2'd1;
            4'd2: theme_family = 2'd2;
            default: theme_family = 2'd0;
        endcase
    end
endfunction

function [23:0] themed_bar_color;
    input [3:0] index;
    input [9:0] x;
    begin
        case (theme_family(index))
            2'd1: begin
                case (x[9:6])
                    4'd0: themed_bar_color = 24'h287A58;
                    4'd1: themed_bar_color = 24'h319568;
                    4'd2: themed_bar_color = 24'h3FAE7A;
                    4'd3: themed_bar_color = 24'h51C68F;
                    4'd4: themed_bar_color = 24'h63D8A7;
                    4'd5: themed_bar_color = 24'h68DEC0;
                    4'd6: themed_bar_color = 24'h5DD6D0;
                    4'd7: themed_bar_color = 24'h53C5D9;
                    4'd8: themed_bar_color = 24'h4AAFE0;
                    default: themed_bar_color = 24'h468FD0;
                endcase
            end
            2'd2: begin
                case (x[9:6])
                    4'd0: themed_bar_color = 24'h5F7F7A;
                    4'd1: themed_bar_color = 24'h708F84;
                    4'd2: themed_bar_color = 24'h82A08D;
                    4'd3: themed_bar_color = 24'h96AF9A;
                    4'd4: themed_bar_color = 24'hA9B9A8;
                    4'd5: themed_bar_color = 24'hB7B6A4;
                    4'd6: themed_bar_color = 24'hC3A58F;
                    4'd7: themed_bar_color = 24'hCC9279;
                    4'd8: themed_bar_color = 24'hB87F72;
                    default: themed_bar_color = 24'h7C98AB;
                endcase
            end
            default: begin
                case (x[9:6])
                    4'd0: themed_bar_color = 24'h5D95D8;
                    4'd1: themed_bar_color = 24'h6CA5E5;
                    4'd2: themed_bar_color = 24'h7AB2EC;
                    4'd3: themed_bar_color = 24'h879CE2;
                    4'd4: themed_bar_color = 24'h9A87D6;
                    4'd5: themed_bar_color = 24'hB77FC5;
                    4'd6: themed_bar_color = 24'hD282A8;
                    4'd7: themed_bar_color = 24'hE49483;
                    4'd8: themed_bar_color = 24'hE9AD63;
                    default: themed_bar_color = 24'hD4C34F;
                endcase
            end
        endcase
    end
endfunction

always @(posedge pixel_clk) begin
    if (pixel_rst) begin
        snapshot_frame_count <= SNAPSHOT_FRAME_DIV - 1;
    end else begin
        if (frame_boundary) begin
            if (snapshot_frame_count == SNAPSHOT_FRAME_DIV - 1)
                snapshot_frame_count <= 8'd0;
            else
                snapshot_frame_count <= snapshot_frame_count + 1'b1;
        end

    end

    if (audio_valid)
        sample_memory[sample_write_ptr] <= sample_level;
    if (!GATE_SAMPLE_READ || sample_read_enable)
        sample_read_data <= sample_memory[sample_index];

    hs_q <= hs_d;
    vs_q <= vs_d;
    de_q <= de_d;
    rgb_q <= rgb_d;
    wave_region_q <= wave_region;
    bar_pixel_q <= bar_pixel;
    bar_color_q <= themed_bar_color(frame_theme_index, pixel_x_d);

end

always @(posedge pixel_clk or posedge pixel_rst) begin
    if (pixel_rst) begin
        sample_write_ptr <= 8'd0;
        sample_read_base <= 8'd0;
        frame_overlay_enable <= 1'b0;
        frame_theme_index <= 4'd0;
        pixel_x <= 10'd0;
        pixel_y <= 10'd0;
        input_de_d <= 1'b0;
        pixel_x_d <= 10'd0;
        pixel_y_d <= 10'd0;
        hs_d <= 1'b0;
        vs_d <= 1'b0;
        de_d <= 1'b0;
        rgb_d <= 24'd0;
        out_hs <= 1'b0;
        out_vs <= 1'b0;
        out_de <= 1'b0;
        out_rgb <= 24'd0;
    end else begin
        if (audio_valid)
            sample_write_ptr <= sample_write_ptr + 1'b1;

        hs_d <= in_hs;
        vs_d <= in_vs;
        de_d <= in_de;
        rgb_d <= in_rgb;
        pixel_x_d <= pixel_x;
        pixel_y_d <= pixel_y;

        out_hs <= hs_q;
        out_vs <= vs_q;
        out_de <= de_q;
        out_rgb <= de_q ?
            (bar_pixel_q ? bar_color_q :
             (wave_region_q ? panel_rgb : rgb_q)) :
            24'd0;
        input_de_d <= in_de;

        if (in_de) begin
            pixel_x <= pixel_x + 1'b1;
        end else begin
            pixel_x <= 10'd0;
            if (input_de_d && (pixel_y < FRAME_HEIGHT - 1))
                pixel_y <= pixel_y + 1'b1;
        end

        if (frame_boundary) begin
            if (snapshot_frame_count == SNAPSHOT_FRAME_DIV - 1) begin
                sample_read_base <= sample_write_ptr;
            end
            frame_overlay_enable <= overlay_enable;
            frame_theme_index <= theme_index;
            pixel_x <= 10'd0;
            pixel_y <= 10'd0;
        end
    end
end

endmodule
