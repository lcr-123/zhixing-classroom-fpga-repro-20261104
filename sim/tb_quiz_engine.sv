`timescale 1ns/1ps

module tb_quiz_engine;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg session_clear = 1'b0;
    reg submit_valid = 1'b0;
    reg feedback_done = 1'b0;
    reg review_mode = 1'b0;
    reg [2:0] question_index = 3'd0;
    reg [1:0] selected_answer = 2'd0;
    reg [1:0] expected_answer = 2'd0;
    reg [2:0] question_count = 3'd4;
    wire submit_accepted;
    wire answer_correct;
    wire answer_locked;
    wire mark_wrong_pulse;
    wire mark_correct_pulse;
    wire quiz_complete;
    wire [3:0] answered_count;
    wire [3:0] correct_count;
    wire [3:0] current_streak;
    wire [3:0] max_streak;
    wire [7:0] score_percent;
    wire [1:0] star_level;
    wire [3:0] answered_bitmap;
    wire [3:0] wrong_bitmap;
    wire [3:0] wrong_count;
    wire wrong_available;
    wire [2:0] first_wrong_question;

    always #5 clk = ~clk;

    quiz_engine quiz (
        .clk(clk), .rst(rst), .session_clear(session_clear),
        .submit_valid(submit_valid), .feedback_done(feedback_done),
        .review_mode(review_mode), .question_index(question_index),
        .selected_answer(selected_answer), .expected_answer(expected_answer),
        .question_count(question_count), .submit_accepted(submit_accepted),
        .answer_correct(answer_correct), .answer_locked(answer_locked),
        .mark_wrong_pulse(mark_wrong_pulse),
        .mark_correct_pulse(mark_correct_pulse),
        .quiz_complete(quiz_complete), .answered_count(answered_count),
        .correct_count(correct_count), .current_streak(current_streak),
        .max_streak(max_streak), .score_percent(score_percent),
        .star_level(star_level), .answered_bitmap(answered_bitmap)
    );

    wrong_question_queue queue (
        .clk(clk), .rst(rst), .clear_all(session_clear),
        .set_wrong(mark_wrong_pulse), .clear_wrong(mark_correct_pulse),
        .question_index(question_index), .wrong_bitmap(wrong_bitmap),
        .wrong_count(wrong_count), .wrong_available(wrong_available),
        .first_wrong_question(first_wrong_question)
    );

    task automatic pulse(ref reg signal);
        begin
            @(negedge clk);
            signal = 1'b1;
            @(negedge clk);
            signal = 1'b0;
            #1;
        end
    endtask

    task automatic submit(
        input [2:0] index,
        input [1:0] selected,
        input [1:0] expected,
        input       review
    );
        begin
            question_index = index;
            selected_answer = selected;
            expected_answer = expected;
            review_mode = review;
            pulse(submit_valid);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        pulse(session_clear);
        if (answered_count != 0 || correct_count != 0 || wrong_available ||
            quiz_complete)
            $fatal(1, "session clear did not reset quiz state");

        // Q0 correct. A duplicate before feedback must be rejected.
        submit(3'd0, 2'd0, 2'd0, 1'b0);
        if (!submit_accepted || !answer_correct || !mark_correct_pulse ||
            answered_count != 1 || correct_count != 1 || current_streak != 1)
            $fatal(2, "correct answer accounting failed");
        submit(3'd0, 2'd1, 2'd0, 1'b0);
        if (submit_accepted || answered_count != 1)
            $fatal(3, "duplicate answer was accepted");
        pulse(feedback_done);

        // A reopened primary question replaces its old correctness without
        // increasing the number of answered questions.
        submit(3'd0, 2'd1, 2'd0, 1'b0);
        if (!submit_accepted || answer_correct || answered_count != 1 ||
            correct_count != 0 || !mark_wrong_pulse)
            $fatal(3, "reopened correct-to-wrong answer was not replaced");
        pulse(feedback_done);
        submit(3'd0, 2'd0, 2'd0, 1'b0);
        if (!submit_accepted || !answer_correct || answered_count != 1 ||
            correct_count != 1 || !mark_correct_pulse)
            $fatal(3, "reopened wrong-to-correct answer was not replaced");
        pulse(feedback_done);

        // Q1 wrong creates one queue entry and resets the streak.
        submit(3'd1, 2'd0, 2'd1, 1'b0);
        if (!submit_accepted || answer_correct || !mark_wrong_pulse ||
            current_streak != 0)
            $fatal(4, "wrong answer accounting failed");
        pulse(feedback_done);
        if (wrong_count != 1 || first_wrong_question != 3'd1)
            $fatal(4, "wrong answer was not committed to the queue");

        // Finish Q2/Q3: two correct total out of four gives 50% and two stars.
        submit(3'd2, 2'd2, 2'd2, 1'b0);
        pulse(feedback_done);
        submit(3'd3, 2'd0, 2'd3, 1'b0);
        if (!quiz_complete || answered_count != 4 || correct_count != 2 ||
            score_percent != 8'd50 || star_level != 2'd2)
            $fatal(5, "quiz completion summary failed");
        pulse(feedback_done);
        if (wrong_count != 2 || wrong_bitmap != 4'b1010)
            $fatal(5, "final wrong answer was not committed");

        // Wrong review keeps the score unchanged; a correct retry clears Q1.
        review_mode = 1'b1;
        submit(3'd1, 2'd0, 2'd1, 1'b1);
        if (!submit_accepted || answer_correct || wrong_count != 2)
            $fatal(6, "wrong review retry changed unexpectedly");
        pulse(feedback_done);
        submit(3'd1, 2'd1, 2'd1, 1'b1);
        if (!submit_accepted || !answer_correct || correct_count != 2)
            $fatal(7, "correct review retry did not clear Q1");
        pulse(feedback_done);
        if (wrong_count != 1 || first_wrong_question != 3'd3)
            $fatal(7, "correct review retry did not clear Q1");

        // Invalid question indices never produce a submission pulse.
        submit(3'd7, 2'd0, 2'd0, 1'b1);
        if (submit_accepted || wrong_count != 1)
            $fatal(8, "invalid question index was accepted");

        // Correct the final wrong question and verify an empty queue.
        submit(3'd3, 2'd3, 2'd3, 1'b1);
        if (!submit_accepted)
            $fatal(9, "wrong queue did not empty after correction");
        pulse(feedback_done);
        if (wrong_available || wrong_count != 0)
            $fatal(9, "wrong queue did not empty after correction");

        // A new session clears both the score and the wrong bitmap.
        pulse(session_clear);
        if (answered_count != 0 || correct_count != 0 || wrong_count != 0 ||
            answered_bitmap != 4'b0000 || quiz_complete)
            $fatal(10, "new session did not clear all state");

        // Three-question percentage mapping uses exact integer percentages.
        question_count = 3'd3;
        pulse(session_clear);
        submit(3'd0, 2'd0, 2'd0, 1'b0);
        pulse(feedback_done);
        submit(3'd1, 2'd1, 2'd1, 1'b0);
        if (score_percent != 8'd66 || correct_count != 2)
            $fatal(11, "three-question percentage mapping failed at 66%%");
        pulse(feedback_done);
        submit(3'd2, 2'd2, 2'd2, 1'b0);
        if (!quiz_complete || score_percent != 8'd100 || star_level != 2'd3)
            $fatal(12, "three-question percentage mapping failed at 100%%");

        // Empty course is safely complete and cannot accept answers.
        question_count = 3'd0;
        submit(3'd0, 2'd0, 2'd0, 1'b0);
        if (!quiz_complete || submit_accepted)
            $fatal(13, "empty course safety policy failed");

        $display("TEST_PASS tb_quiz_engine");
        $finish;
    end
endmodule
