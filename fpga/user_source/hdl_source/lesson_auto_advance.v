`timescale 1ns/1ps

// Advances learning pages only after narration has actually drained in the
// audio clock domain.  The asynchronous active level is synchronized here;
// a remembered page tag prevents a manual page change from turning the old
// narration's falling edge into a second, unintended page advance.
module lesson_auto_advance (
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] app_state,
    input  wire [2:0] page_index,
    input  wire       voice_active_async,
    input  wire       voice_complete_async,
    output reg        auto_next_pulse
);

localparam [3:0] ST_LEARN = 4'd2;
// The third and final learning page stays visible for KEY4 confirmation.
localparam [2:0] LAST_AUTO_PAGE = 3'd1;

reg voice_active_meta /* fehdl keep="true" */;
reg voice_active_sync /* fehdl keep="true" */;
reg voice_active_prev;
reg voice_complete_meta /* fehdl keep="true" */;
reg voice_complete_sync /* fehdl keep="true" */;
reg completion_armed;
reg [2:0] armed_page;

wire learning_page_can_advance =
    (app_state == ST_LEARN) && (page_index <= LAST_AUTO_PAGE);
wire voice_started = voice_active_sync && !voice_active_prev;
wire voice_finished = !voice_active_sync && voice_active_prev;

always @(posedge clk) begin
    if (rst) begin
        voice_active_meta <= 1'b0;
        voice_active_sync <= 1'b0;
        voice_active_prev <= 1'b0;
        voice_complete_meta <= 1'b0;
        voice_complete_sync <= 1'b0;
        completion_armed  <= 1'b0;
        armed_page        <= 3'd0;
        auto_next_pulse   <= 1'b0;
    end else begin
        // Register the completion event so a narration falling edge cannot
        // be sampled on the same edge as entry into the quiz state.
        auto_next_pulse <= learning_page_can_advance &&
                           completion_armed &&
                           voice_complete_sync &&
                           (page_index == armed_page) &&
                           voice_finished;
        voice_active_meta <= voice_active_async;
        voice_active_sync <= voice_active_meta;
        voice_active_prev <= voice_active_sync;
        voice_complete_meta <= voice_complete_async;
        voice_complete_sync <= voice_complete_meta;

        if (!learning_page_can_advance ||
            (completion_armed && (page_index != armed_page))) begin
            completion_armed <= 1'b0;
        end else if (voice_started) begin
            completion_armed <= 1'b1;
            armed_page <= page_index;
        end else if (auto_next_pulse) begin
            completion_armed <= 1'b0;
        end
    end
end

endmodule
