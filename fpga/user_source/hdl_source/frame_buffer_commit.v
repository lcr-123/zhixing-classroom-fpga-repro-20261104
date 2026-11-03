`timescale 1ns/1ps

module frame_buffer_commit #(
    parameter integer TRANSITION_STEPS = 16
) (
    input  wire       pixel_clk,
    input  wire       pixel_rst,
    input  wire       frame_boundary,
    input  wire [1:0] source_buf_idx,
    input  wire [3:0] source_image_idx,
    input  wire       source_page_right,
    input  wire       source_settings_entry,
    input  wire [2:0] source_zoom_level,
    input  wire       source_display_valid,
    input  wire       source_commit_toggle,
    output reg        commit_ack_toggle,
    output reg  [1:0] display_buf_idx,
    output reg  [1:0] transition_buf_idx,
    output reg  [3:0] display_image_idx,
    output reg  [2:0] display_zoom_level,
    output reg        display_valid,
    output wire       lesson_image_ready,
    output reg        transition_active,
    output reg  [4:0] transition_alpha,
    output reg  [1:0] transition_effect
);

localparam [1:0] TRANSITION_FADE      = 2'd0;
localparam [1:0] TRANSITION_SHATTER   = 2'd1;
localparam [1:0] TRANSITION_PAGE_LEFT = 2'd2;
localparam [1:0] TRANSITION_PAGE_RIGHT = 2'd3;
localparam integer ALPHA_STEP = 16 / TRANSITION_STEPS;
localparam integer LAST_ALPHA = 16 - ALPHA_STEP;

reg [2:0] request_sync /* fehdl keep="true" */;
reg [1:0] index_meta /* fehdl keep="true" */;
reg [1:0] index_sync /* fehdl keep="true" */;
reg [3:0] image_meta /* fehdl keep="true" */;
reg [3:0] image_sync /* fehdl keep="true" */;
reg       page_right_meta /* fehdl keep="true" */;
reg       page_right_sync /* fehdl keep="true" */;
reg       settings_meta /* fehdl keep="true" */;
reg       settings_sync /* fehdl keep="true" */;
reg [2:0] zoom_meta /* fehdl keep="true" */;
reg [2:0] zoom_sync /* fehdl keep="true" */;
reg       valid_meta /* fehdl keep="true" */;
reg       valid_sync /* fehdl keep="true" */;
reg       request_seen;
reg       commit_pending;
reg [1:0] pending_index;
reg [3:0] pending_image;
reg       pending_page_right;
reg       pending_settings_entry;
reg [2:0] pending_zoom;
reg       pending_valid;
reg       pending_toggle;
reg [3:0] transition_image_idx;
reg [2:0] transition_zoom_level;
reg       transition_valid;
reg       transition_toggle;

assign lesson_image_ready =
    (display_valid && (display_image_idx < 4'd3) &&
     (!transition_active || (transition_image_idx < 4'd3))) ||
    (transition_active && transition_valid &&
     (transition_image_idx < 4'd3) &&
     (transition_alpha >= LAST_ALPHA));

always @(posedge pixel_clk or posedge pixel_rst) begin
    if (pixel_rst) begin
        request_sync     <= 3'b000;
        index_meta       <= 2'd0;
        index_sync       <= 2'd0;
        image_meta       <= 4'd0;
        image_sync       <= 4'd0;
        page_right_meta  <= 1'b0;
        page_right_sync  <= 1'b0;
        settings_meta <= 1'b0;
        settings_sync <= 1'b0;
        zoom_meta        <= 3'd2;
        zoom_sync        <= 3'd2;
        valid_meta       <= 1'b0;
        valid_sync       <= 1'b0;
        request_seen     <= 1'b0;
        commit_pending   <= 1'b0;
        pending_index    <= 2'd0;
        pending_image    <= 4'd0;
        pending_page_right <= 1'b0;
        pending_settings_entry <= 1'b0;
        pending_zoom     <= 3'd2;
        pending_valid    <= 1'b0;
        pending_toggle   <= 1'b0;
        commit_ack_toggle <= 1'b0;
        display_buf_idx  <= 2'd0;
        transition_buf_idx <= 2'd0;
        display_image_idx <= 4'd0;
        display_zoom_level <= 3'd2;
        display_valid    <= 1'b0;
        transition_active <= 1'b0;
        transition_alpha <= 5'd0;
        transition_effect <= TRANSITION_FADE;
        transition_image_idx <= 4'd0;
        transition_zoom_level <= 3'd2;
        transition_valid <= 1'b0;
        transition_toggle <= 1'b0;
    end else begin
        request_sync <= {request_sync[1:0], source_commit_toggle};
        index_meta   <= source_buf_idx;
        index_sync   <= index_meta;
        image_meta   <= source_image_idx;
        image_sync   <= image_meta;
        page_right_meta <= source_page_right;
        page_right_sync <= page_right_meta;
        settings_meta <= source_settings_entry;
        settings_sync <= settings_meta;
        zoom_meta    <= source_zoom_level;
        zoom_sync    <= zoom_meta;
        valid_meta   <= source_display_valid;
        valid_sync   <= valid_meta;

        if (request_sync[2] != request_seen) begin
            request_seen   <= request_sync[2];
            commit_pending <= 1'b1;
            pending_index  <= index_sync;
            pending_image  <= image_sync;
            pending_page_right <= page_right_sync;
            pending_settings_entry <= settings_sync;
            pending_zoom   <= zoom_sync;
            pending_valid  <= valid_sync;
            pending_toggle <= request_sync[2];
        end

        if (frame_boundary) begin
            if (transition_active) begin
                if (transition_alpha >= LAST_ALPHA) begin
                    display_buf_idx <= transition_buf_idx;
                    display_image_idx <= transition_image_idx;
                    display_zoom_level <= transition_zoom_level;
                    display_valid <= transition_valid;
                    transition_active <= 1'b0;
                    transition_alpha <= 5'd0;
                    transition_effect <= TRANSITION_FADE;
                    commit_ack_toggle <= transition_toggle;
                end else begin
                    transition_alpha <= transition_alpha + ALPHA_STEP;
                end
            end else if (commit_pending) begin
                commit_pending <= 1'b0;
                if (!display_valid ||
                    !pending_valid ||
                    (pending_index == display_buf_idx) ||
                    ((pending_image == display_image_idx) &&
                     (pending_zoom != display_zoom_level))) begin
                    display_buf_idx <= pending_index;
                    transition_buf_idx <= pending_index;
                    display_image_idx <= pending_image;
                    display_zoom_level <= pending_zoom;
                    display_valid <= pending_valid;
                    commit_ack_toggle <= pending_toggle;
                end else begin
                    transition_buf_idx <= pending_index;
                    transition_image_idx <= pending_image;
                    transition_zoom_level <= pending_zoom;
                    transition_valid <= pending_valid;
                    transition_toggle <= pending_toggle;
                    transition_active <= 1'b1;
                    transition_alpha <= ALPHA_STEP;
                    // Learning-page direction is selected from the committed
                    // image and the complete pending image at the frame edge.
                    transition_effect <=
                        ((display_image_idx == 4'd12) &&
                         (pending_image == 4'd0) &&
                         !pending_settings_entry) ?
                        TRANSITION_PAGE_LEFT :
                        ((display_image_idx == 4'd0) &&
                         (pending_image == 4'd1)) ?
                        TRANSITION_PAGE_LEFT :
                        ((display_image_idx == 4'd2) &&
                         (pending_image == 4'd1)) ?
                        TRANSITION_PAGE_RIGHT :
                        ((display_image_idx == 4'd1) &&
                         (pending_image == 4'd2)) ?
                        TRANSITION_SHATTER :
                        ((pending_image >= 4'd3) ?
                         (pending_page_right ? TRANSITION_PAGE_RIGHT :
                                               TRANSITION_PAGE_LEFT) :
                         TRANSITION_FADE);
                end
            end
        end
    end
end

endmodule
