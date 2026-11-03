`timescale 1ns/1ps

// Metadata for the fixed English nature package.  Image indices are zero
// based: 0..2 are learning pages and 3..11 are exercise-pool pages.
// Answers use A=0, B=1, C=2, D=3.
module english_nature_course_rom (
    input  wire [3:0] image_index,
    input  wire [3:0] available_count,
    output reg        card_valid,
    output reg        safe_home_request,
    output reg        learning_page,
    output reg        question_page,
    output reg  [1:0] question_group,
    output reg  [1:0] group_index,
    output reg  [1:0] correct_answer,
    output reg [10:0] expected_width,
    output reg  [9:0] expected_height
);

localparam [1:0] GROUP_VOCABULARY = 2'd0;
localparam [1:0] GROUP_SENTENCE   = 2'd1;
localparam [1:0] GROUP_QUESTION   = 2'd2;

always @* begin
    card_valid       = 1'b0;
    safe_home_request = 1'b1;
    learning_page    = 1'b0;
    question_page    = 1'b0;
    question_group   = GROUP_VOCABULARY;
    group_index      = 2'd0;
    correct_answer   = 2'd0;
    expected_width   = 11'd0;
    expected_height  = 10'd0;

    if ((available_count >= 4'd3) &&
        (image_index < available_count) &&
        (image_index < 4'd12)) begin
        card_valid        = 1'b1;
        safe_home_request = 1'b0;
        expected_width    = 11'd640;
        expected_height   = 10'd480;

        if (image_index < 4'd3) begin
            learning_page = 1'b1;
        end else begin
            question_page = 1'b1;
            if (image_index < 4'd6) begin
                expected_width = 11'd1280;
                expected_height = 10'd960;
            end else if (image_index < 4'd9) begin
                expected_width = 11'd800;
                expected_height = 10'd600;
            end else begin
                expected_width = 11'd320;
                expected_height = 10'd240;
            end
            case (image_index)
                4'd3: begin question_group = GROUP_VOCABULARY; group_index = 2'd0; correct_answer = 2'd2; end
                4'd4: begin question_group = GROUP_VOCABULARY; group_index = 2'd1; correct_answer = 2'd1; end
                4'd5: begin question_group = GROUP_VOCABULARY; group_index = 2'd2; correct_answer = 2'd3; end
                4'd6: begin question_group = GROUP_SENTENCE;   group_index = 2'd0; correct_answer = 2'd1; end
                4'd7: begin question_group = GROUP_SENTENCE;   group_index = 2'd1; correct_answer = 2'd0; end
                4'd8: begin question_group = GROUP_SENTENCE;   group_index = 2'd2; correct_answer = 2'd2; end
                4'd9: begin question_group = GROUP_QUESTION;   group_index = 2'd0; correct_answer = 2'd0; end
                4'd10: begin question_group = GROUP_QUESTION;  group_index = 2'd1; correct_answer = 2'd2; end
                4'd11: begin question_group = GROUP_QUESTION;  group_index = 2'd2; correct_answer = 2'd3; end
                default: begin
                    card_valid        = 1'b0;
                    safe_home_request = 1'b1;
                    question_page     = 1'b0;
                    expected_width    = 11'd0;
                    expected_height   = 10'd0;
                end
            endcase
        end
    end
end

endmodule
