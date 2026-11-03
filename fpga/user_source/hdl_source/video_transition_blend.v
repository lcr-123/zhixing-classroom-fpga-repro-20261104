`timescale 1ns/1ps

module video_transition_blend (
    input  wire        pixel_clk,
    input  wire        pixel_rst,
    input  wire        frame_boundary,
    input  wire        in_de,
    input  wire [23:0] current_rgb,
    input  wire [23:0] next_rgb,
    input  wire        transition_active,
    input  wire [4:0]  transition_alpha,
    input  wire [1:0]  transition_effect,
    output wire [23:0] blended_rgb
);

localparam [1:0] TRANSITION_FADE      = 2'd0;
localparam [1:0] TRANSITION_SHATTER   = 2'd1;
localparam [1:0] TRANSITION_PAGE_LEFT = 2'd2;
localparam [1:0] TRANSITION_PAGE_RIGHT = 2'd3;

reg [9:0] pixel_x;
reg [8:0] pixel_y;

// Coordinates advance only across the active 640x480 picture.  The upstream
// frame boundary occurs in blanking, so every effect starts from a known
// origin without adding latency to the RGB path.
always @(posedge pixel_clk or posedge pixel_rst) begin
    if (pixel_rst) begin
        pixel_x <= 10'd0;
        pixel_y <= 9'd0;
    end else if (frame_boundary) begin
        pixel_x <= 10'd0;
        pixel_y <= 9'd0;
    end else if (in_de) begin
        if (pixel_x == 10'd639) begin
            pixel_x <= 10'd0;
            if (pixel_y == 9'd479)
                pixel_y <= 9'd0;
            else
                pixel_y <= pixel_y + 1'b1;
        end else begin
            pixel_x <= pixel_x + 1'b1;
        end
    end
end

function [7:0] blend_channel;
    input [7:0] current_value;
    input [7:0] next_value;
    input [4:0] alpha;
    reg [12:0] weighted;
    begin
        weighted = current_value * (5'd16 - alpha) +
                   next_value * alpha + 5'd8;
        blend_channel = weighted[11:4];
    end
endfunction

// Isolate the multiply/add pixel operands outside transitions.
// Keep the combinational latency: the display/commit pipeline is unchanged.
wire [23:0] fade_current_rgb = transition_active ? current_rgb : 24'd0;
wire [23:0] fade_next_rgb = transition_active ? next_rgb : 24'd0;
wire [23:0] fade_rgb = {
    blend_channel(fade_current_rgb[23:16], fade_next_rgb[23:16], transition_alpha),
    blend_channel(fade_current_rgb[15:8], fade_next_rgb[15:8], transition_alpha),
    blend_channel(fade_current_rgb[7:0], fade_next_rgb[7:0], transition_alpha)
};

// Split every 32x32 cell into two diagonal fragments.  A coordinate hash
// assigns each fragment a deterministic reveal frame from 1 to 15, producing
// a repeatable broken-screen transition without frame-sized storage, divide,
// or random state.  Only fragments at the active reveal front receive a thin
// icy highlight, so the cracks disappear completely after commit.
wire [4:0] tile_x = pixel_x[9:5];
wire [3:0] tile_y = pixel_y[8:5];
wire [4:0] local_x = pixel_x[4:0];
wire [4:0] local_y = pixel_y[4:0];
wire [5:0] local_sum = {1'b0, local_x} + {1'b0, local_y};
wire tile_orientation = tile_x[0] ^ tile_y[0];
wire shard_half = tile_orientation ?
                  (local_x >= local_y) : (local_sum >= 6'd32);
wire [3:0] shard_hash_raw = tile_x[3:0] ^
                            {tile_y[2:0], tile_y[3]} ^
                            {tile_x[0], tile_y[0], tile_x[2], tile_y[2]} ^
                            (shard_half ? 4'hB : 4'h3);
wire [3:0] shard_threshold =
    (shard_hash_raw == 4'd0) ? 4'd1 : shard_hash_raw;
wire shard_revealed = transition_alpha[3:0] >= shard_threshold;
wire crack_diagonal = tile_orientation ?
                      ((local_x == local_y) ||
                       (local_x + 1'b1 == local_y) ||
                       (local_y + 1'b1 == local_x)) :
                      ((local_sum >= 6'd30) && (local_sum <= 6'd32));
wire reveal_front = (transition_alpha[3:0] == shard_threshold) &&
                    (transition_alpha < 5'd15);
wire [23:0] shatter_rgb = (reveal_front && crack_diagonal) ?
                          24'hD8F4FF :
                          (shard_revealed ? next_rgb : current_rgb);

// Practice pages use a right-to-left page turn.  The leading edge bows
// slightly at the top and bottom, while a narrow old-page shadow and a bright
// new-page rim make the wipe read as a physical sheet moving left.  The
// 40-pixel-per-frame step covers the 640-pixel picture in the existing
// 16-frame transition window and requires no additional frame storage.
reg [4:0] page_curve;
always @(*) begin
    case (pixel_y[8:6])
        3'd0, 3'd7: page_curve = 5'd16;
        3'd1, 3'd6: page_curve = 5'd12;
        3'd2, 3'd5: page_curve = 5'd6;
        default:    page_curve = 5'd0;
    endcase
end

wire [10:0] page_shift = {1'b0, transition_alpha, 5'b0} +
                          {3'b000, transition_alpha, 3'b000};
wire [10:0] page_base = 11'd640 - page_shift;
wire [10:0] page_edge_unclamped = page_base + {6'd0, page_curve};
wire [10:0] page_edge = (page_edge_unclamped > 11'd640) ?
                        11'd640 : page_edge_unclamped;
wire [10:0] page_shadow_start = (page_edge > 11'd12) ?
                                (page_edge - 11'd12) : 11'd0;
wire [10:0] pixel_x_ext = {1'b0, pixel_x};
wire page_shadow = (pixel_x_ext >= page_shadow_start) &&
                   (pixel_x_ext < page_edge);
wire page_new_side = pixel_x_ext >= page_edge;
wire page_rim = page_new_side &&
                (pixel_x_ext < (page_edge + 11'd3));
wire [23:0] page_shadow_rgb = {
    1'b0, current_rgb[23:17],
    1'b0, current_rgb[15:9],
    1'b0, current_rgb[7:1]
};
wire [23:0] page_left_rgb = page_rim ? 24'hE8F2FF :
                            (page_new_side ? next_rgb :
                             (page_shadow ? page_shadow_rgb : current_rgb));
wire [10:0] page_right_edge = 11'd640 - page_edge;
wire page_right_new_side = pixel_x_ext < page_right_edge;
wire page_right_rim = page_right_new_side &&
                      (pixel_x_ext + 11'd3 >= page_right_edge);
wire page_right_shadow = (pixel_x_ext >= page_right_edge) &&
                         (pixel_x_ext < page_right_edge + 11'd12);
wire [23:0] page_right_rgb = page_right_rim ? 24'hE8F2FF :
                             (page_right_new_side ? next_rgb :
                              (page_right_shadow ? page_shadow_rgb : current_rgb));

assign blended_rgb = !transition_active ? current_rgb :
                     ((transition_effect == TRANSITION_SHATTER) ?
                      shatter_rgb :
                      ((transition_effect == TRANSITION_PAGE_LEFT) ?
                       page_left_rgb :
                       ((transition_effect == TRANSITION_PAGE_RIGHT) ?
                        page_right_rgb : fade_rgb)));

endmodule
