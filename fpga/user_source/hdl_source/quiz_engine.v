`timescale 1ns/1ps

// Application-layer quiz scoring and answer acceptance.
// A submission remains locked until the feedback stage acknowledges it.
// Primary questions may be reopened later; a replacement answer updates the
// stored correctness bit without increasing the answered count. Review
// answers update the wrong bitmap but do not alter the primary quiz score.
module quiz_engine #(
    parameter integer QUESTION_COUNT = 4
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         session_clear,
    input  wire                         submit_valid,
    input  wire                         feedback_done,
    input  wire                         review_mode,
    input  wire [2:0]                   question_index,
    input  wire [1:0]                   selected_answer,
    input  wire [1:0]                   expected_answer,
    input  wire [2:0]                   question_count,
    output reg                          submit_accepted,
    output reg                          answer_correct,
    output reg                          answer_locked,
    output reg                          mark_wrong_pulse,
    output reg                          mark_correct_pulse,
    output reg                          quiz_complete,
    output reg  [3:0]                   answered_count,
    output reg  [3:0]                   correct_count,
    output reg  [3:0]                   current_streak,
    output reg  [3:0]                   max_streak,
    output reg  [7:0]                   score_percent,
    output reg  [1:0]                   star_level,
    output wire [QUESTION_COUNT-1:0]    answered_bitmap
);

    reg [QUESTION_COUNT-1:0] answered_bitmap_reg;
    reg [QUESTION_COUNT-1:0] correct_bitmap_reg;
    reg [2:0] active_count;
    integer ratio_numerator;
    integer i;
    integer running_streak;

    assign answered_bitmap = answered_bitmap_reg;

    always @* begin
        if (question_count > QUESTION_COUNT)
            active_count = QUESTION_COUNT[2:0];
        else
            active_count = question_count;

        answered_count = 4'd0;
        correct_count = 4'd0;
        current_streak = 4'd0;
        ratio_numerator = 0;
        max_streak = 4'd0;
        running_streak = 0;
        for (i = 0; i < QUESTION_COUNT; i = i + 1) begin
            if (i < active_count) begin
                if (answered_bitmap_reg[i])
                    answered_count = answered_count + 4'd1;
                if (correct_bitmap_reg[i])
                    correct_count = correct_count + 4'd1;

                if (answered_bitmap_reg[i]) begin
                    if (correct_bitmap_reg[i]) begin
                        running_streak = running_streak + 1;
                        current_streak = running_streak;
                        if (running_streak > max_streak)
                            max_streak = running_streak;
                    end else begin
                        running_streak = 0;
                        current_streak = 4'd0;
                    end
                end
            end
        end

        // A zero-question course is treated as already complete and never
        // accepts an answer, avoiding an unbounded or divide-by-zero path.
        quiz_complete = (active_count == 3'd0) ||
                        ((active_count != 3'd0) &&
                         (answered_count >= active_count));

        score_percent = 8'd0;
        if (active_count != 3'd0) begin
            case (active_count)
                3'd1: score_percent = (correct_count != 0) ? 8'd100 : 8'd0;
                3'd2: score_percent = correct_count * 8'd50;
                3'd3: begin
                    case (correct_count)
                        4'd0: score_percent = 8'd0;
                        4'd1: score_percent = 8'd33;
                        4'd2: score_percent = 8'd66;
                        default: score_percent = 8'd100;
                    endcase
                end
                default: score_percent = correct_count * 8'd25;
            endcase
        end

        star_level = 2'd0;
        if (active_count != 3'd0) begin
            ratio_numerator = correct_count * 4;
            if (ratio_numerator >= (active_count * 3))
                star_level = 2'd3;
            else if (ratio_numerator >= (active_count * 2))
                star_level = 2'd2;
            else if (correct_count != 0)
                star_level = 2'd1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            answered_bitmap_reg <= {QUESTION_COUNT{1'b0}};
            correct_bitmap_reg <= {QUESTION_COUNT{1'b0}};
            submit_accepted <= 1'b0;
            answer_correct <= 1'b0;
            answer_locked <= 1'b0;
            mark_wrong_pulse <= 1'b0;
            mark_correct_pulse <= 1'b0;
        end else if (session_clear) begin
            answered_bitmap_reg <= {QUESTION_COUNT{1'b0}};
            correct_bitmap_reg <= {QUESTION_COUNT{1'b0}};
            submit_accepted <= 1'b0;
            answer_correct <= 1'b0;
            answer_locked <= 1'b0;
            mark_wrong_pulse <= 1'b0;
            mark_correct_pulse <= 1'b0;
        end else begin
            submit_accepted <= 1'b0;
            mark_wrong_pulse <= 1'b0;
            mark_correct_pulse <= 1'b0;

            if (feedback_done)
                answer_locked <= 1'b0;

            if (submit_valid && !answer_locked &&
                (active_count != 3'd0) &&
                (question_index < active_count)) begin
                submit_accepted <= 1'b1;
                answer_locked <= 1'b1;
                answer_correct <= (selected_answer == expected_answer);

                if (selected_answer == expected_answer) begin
                    mark_correct_pulse <= 1'b1;
                end else begin
                    mark_wrong_pulse <= 1'b1;
                end

                if (!review_mode) begin
                    answered_bitmap_reg[question_index] <= 1'b1;
                    correct_bitmap_reg[question_index] <=
                        (selected_answer == expected_answer);
                end
            end
        end
    end

endmodule
