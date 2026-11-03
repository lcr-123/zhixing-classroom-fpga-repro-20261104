`timescale 1ns/1ps

// Fixed course metadata for four Grade 4A learning cards.  Images 0..3 are
// the learning pages; their paired exercise pages live at image indices 4..7.
// Answer convention is A=0, B=1, C=2, D=3; the interdisciplinary sequence
// is D/B/B/A, with the final A identifying high pitch plus square waveform.
// The table never exposes an image index that is not present in the current
// scan result. Invalid or empty selections request a bounded return to HOME.
module course_content_rom (
    input  wire [2:0] course_index,
    input  wire [2:0] available_count,
    output reg        course_valid,
    output reg        safe_home_request,
    output reg  [2:0] image_index,
    output reg  [2:0] page_number,
    output reg  [1:0] question_id,
    output reg  [1:0] correct_answer,
    output reg  [2:0] next_course_index,
    output reg        auto_play_allowed,
    output reg [10:0] expected_width,
    output reg  [9:0] expected_height
);

wire [2:0] bounded_count = (available_count > 3'd4) ? 3'd4 : available_count;

always @* begin
    course_valid = 1'b0;
    safe_home_request = 1'b1;
    image_index = 3'd0;
    page_number = 3'd0;
    question_id = 2'd0;
    correct_answer = 2'd0;
    next_course_index = 3'd0;
    auto_play_allowed = 1'b0;
    expected_width = 11'd0;
    expected_height = 10'd0;

    if ((bounded_count != 3'd0) &&
        (course_index < bounded_count) &&
        (course_index < 3'd4)) begin
        course_valid = 1'b1;
        safe_home_request = 1'b0;
        image_index = course_index;
        page_number = course_index + 3'd1;
        question_id = course_index[1:0];
        auto_play_allowed = (bounded_count > 3'd1);

        if ((course_index + 3'd1) < bounded_count)
            next_course_index = course_index + 3'd1;
        else
            next_course_index = 3'd0;

        case (course_index)
            3'd0: begin
                correct_answer = 2'd3;
                expected_width = 11'd640;
                expected_height = 10'd480;
            end
            3'd1: begin
                correct_answer = 2'd1;
                expected_width = 11'd640;
                expected_height = 10'd480;
            end
            3'd2: begin
                correct_answer = 2'd1;
                expected_width = 11'd640;
                expected_height = 10'd480;
            end
            3'd3: begin
                correct_answer = 2'd0;
                expected_width = 11'd640;
                expected_height = 10'd480;
            end
            default: begin
                expected_width = 11'd0;
                expected_height = 10'd0;
            end
        endcase
    end
end

endmodule
