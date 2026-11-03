`timescale 1ns/1ps

module tb_learning_controller;
    localparam [3:0] ST_BOOT_SELFTEST = 4'd0;
    localparam [3:0] ST_HOME          = 4'd1;
    localparam [3:0] ST_LEARN         = 4'd2;
    localparam [3:0] ST_QUIZ          = 4'd3;
    localparam [3:0] ST_FEEDBACK      = 4'd4;
    localparam [3:0] ST_WRONG_REVIEW  = 4'd5;
    localparam [3:0] ST_SOUND_LAB     = 4'd6;
    localparam [3:0] ST_SETTINGS      = 4'd7;
    localparam [3:0] ST_SUMMARY       = 4'd8;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg boot_done = 1'b0;
    reg content_ready = 1'b0;
    reg nav_next_pulse = 1'b0;
    reg nav_prev_pulse = 1'b0;
    reg nav_select_pulse = 1'b0;
    reg nav_back_pulse = 1'b0;
    reg home_long_pulse = 1'b0;
    reg answer_valid = 1'b0;
    reg [1:0] answer_code = 2'd0;
    reg feedback_ack_pressed = 1'b0;
    reg feedback_done = 1'b0;
    reg quiz_complete = 1'b0;
    reg wrong_questions_available = 1'b0;
    reg [2:0] page_count = 3'd3;
    wire [3:0] state;
    wire [2:0] menu_index;
    wire [2:0] page_index;
    wire [1:0] selected_answer;
    wire answer_in_review;
    wire answer_submit_pulse;
    wire answer_reopen_pulse;
    wire session_clear_pulse;
    wire safe_recovery_pulse;
    wire practice_prev_change_pulse;
    wire practice_next_change_pulse;
    integer submit_count = 0;

    always #5 clk = ~clk;

    learning_controller dut (
        .clk(clk),
        .rst(rst),
        .boot_done(boot_done),
        .content_ready(content_ready),
        .nav_next_pulse(nav_next_pulse),
        .nav_prev_pulse(nav_prev_pulse),
        .nav_select_pulse(nav_select_pulse),
        .nav_back_pulse(nav_back_pulse),
        .home_long_pulse(home_long_pulse),
        .answer_valid(answer_valid),
        .answer_code(answer_code),
        .feedback_ack_pressed(feedback_ack_pressed),
        .feedback_done(feedback_done),
        .quiz_complete(quiz_complete),
        .wrong_questions_available(wrong_questions_available),
        .page_count(page_count),
        .state(state),
        .menu_index(menu_index),
        .page_index(page_index),
        .selected_answer(selected_answer),
        .answer_in_review(answer_in_review),
        .answer_submit_pulse(answer_submit_pulse),
        .answer_reopen_pulse(answer_reopen_pulse),
        .session_clear_pulse(session_clear_pulse),
        .safe_recovery_pulse(safe_recovery_pulse),
        .practice_prev_change_pulse(practice_prev_change_pulse),
        .practice_next_change_pulse(practice_next_change_pulse)
    );

    always @(posedge clk) begin
        if (answer_submit_pulse)
            submit_count <= submit_count + 1;
    end

    task automatic pulse(ref reg signal);
        begin
            @(negedge clk);
            signal = 1'b1;
            @(negedge clk);
            signal = 1'b0;
            #1;
        end
    endtask

    task automatic expect_state(input [3:0] expected, input integer code);
        begin
            #1;
            if (state !== expected) begin
                $display("CHECK_%0d state mismatch: got %0d expected %0d", code, state, expected);
                $fatal(1);
            end
        end
    endtask

    task automatic acknowledge_feedback;
        begin
            pulse(feedback_ack_pressed);
            pulse(feedback_done);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        pulse(nav_select_pulse);
        expect_state(ST_BOOT_SELFTEST, 1);
        pulse(boot_done);
        expect_state(ST_HOME, 2);

        // Missing content must not enter the course or touch an invalid page.
        pulse(nav_select_pulse);
        expect_state(ST_HOME, 3);
        if (!safe_recovery_pulse)
            $fatal(4, "missing content was not reported");
        content_ready = 1'b1;

        // Learn mode: three pages wrap, previous saturates at the first page,
        // and an empty list is bounded at zero.
        pulse(nav_select_pulse);
        expect_state(ST_LEARN, 3);
        repeat (2) pulse(nav_next_pulse);
        pulse(nav_prev_pulse);
        if (page_index != 3'd1)
            $fatal(4, "learning previous did not return one page");
        pulse(nav_prev_pulse);
        pulse(nav_prev_pulse);
        if (page_index != 3'd0)
            $fatal(4, "learning previous wrapped below the first page");
        repeat (3) pulse(nav_next_pulse);
        if (page_index != 3'd0)
            $fatal(4, "page index did not wrap");
        page_count = 3'd0;
        pulse(nav_next_pulse);
        if (page_index != 3'd0)
            $fatal(5, "empty page list escaped index zero");
        page_count = 3'd3;

        // Enter quiz from learning, accept one answer, and lock feedback input.
        pulse(nav_select_pulse);
        expect_state(ST_QUIZ, 6);
        if (!session_clear_pulse)
            $fatal(7, "new quiz did not clear its session");
        pulse(nav_prev_pulse);
        if (practice_prev_change_pulse || practice_next_change_pulse ||
            (page_index != 3'd0))
            $fatal(7, "first-question previous press produced a false cue");
        answer_code = 2'd2;
        pulse(answer_valid);
        expect_state(ST_FEEDBACK, 8);
        if (selected_answer != 2'd2 || answer_in_review)
            $fatal(9, "quiz answer metadata was not latched");
        repeat (20) @(posedge clk);
        #1;
        if (state != ST_FEEDBACK || page_index != 3'd0 ||
            practice_next_change_pulse)
            $fatal(9, "practice feedback advanced without KEY2 acknowledgement");
        pulse(feedback_done);
        if (state != ST_FEEDBACK || page_index != 3'd0)
            $fatal(9, "stale feedback event advanced the practice question");
        answer_code = 2'd1;
        pulse(answer_valid);
        expect_state(ST_FEEDBACK, 10);
        if (selected_answer != 2'd2)
            $fatal(11, "feedback accepted a repeated answer");
        acknowledge_feedback();
        expect_state(ST_QUIZ, 12);
        if (!practice_next_change_pulse || practice_prev_change_pulse)
            $fatal(12, "real next-question move did not emit next cue");

        // Going back from Q1 to Q0 remembers Q1 as the resume point. The
        // revised answer returns to Q1 after feedback.
        if (page_index != 3'd1)
            $fatal(12, "quiz cursor did not reach question one");
        pulse(nav_prev_pulse);
        if (state != ST_QUIZ || page_index != 3'd0)
            $fatal(12, "quiz previous did not reopen question zero");
        if (!practice_prev_change_pulse || practice_next_change_pulse)
            $fatal(12, "real previous-question move did not emit previous cue");
        answer_code = 2'd0;
        pulse(answer_valid);
        acknowledge_feedback();
        if (state != ST_QUIZ || page_index != 3'd1)
            $fatal(12, "edited answer did not resume the original question");
        if (!practice_next_change_pulse || practice_prev_change_pulse)
            $fatal(12, "edited answer resume did not emit next cue");

        // Simultaneous back and answer gives navigation priority and no score.
        @(negedge clk);
        nav_back_pulse = 1'b1;
        answer_valid = 1'b1;
        @(negedge clk);
        nav_back_pulse = 1'b0;
        answer_valid = 1'b0;
        expect_state(ST_HOME, 13);
        if (submit_count != 2)
            $fatal(14, "simultaneous back and answer changed the score");

        // HOME has no direct quiz entry; the first KEY2 selects review.
        pulse(nav_next_pulse);
        if (menu_index != 3'd1)
            $fatal(15, "removed HOME quiz entry is still selectable");
        pulse(nav_select_pulse);
        expect_state(ST_SUMMARY, 15);
        if (session_clear_pulse)
            $fatal(15, "HOME review selection started a quiz session");
        pulse(nav_select_pulse);
        expect_state(ST_HOME, 15);

        repeat (2) pulse(nav_next_pulse);
        if (menu_index != 3'd2)
            $fatal(15, "home menu indexing failed");
        pulse(nav_select_pulse);
        expect_state(ST_SETTINGS, 16);
        pulse(nav_back_pulse);
        expect_state(ST_HOME, 17);

        repeat (3) pulse(nav_next_pulse);
        pulse(nav_select_pulse);
        expect_state(ST_SUMMARY, 20);
        pulse(nav_select_pulse);
        expect_state(ST_HOME, 21);

        // Wrong-review path keeps the origin across feedback and exits safely
        // when the queue becomes empty.
        wrong_questions_available = 1'b1;
        pulse(nav_next_pulse);
        pulse(nav_select_pulse);
        expect_state(ST_WRONG_REVIEW, 22);
        answer_code = 2'd3;
        pulse(answer_valid);
        expect_state(ST_FEEDBACK, 23);
        if (!answer_in_review || selected_answer != 2'd3)
            $fatal(24, "review answer metadata was not latched");
        acknowledge_feedback();
        expect_state(ST_WRONG_REVIEW, 25);
        wrong_questions_available = 1'b0;
        @(posedge clk);
        #1;
        expect_state(ST_HOME, 26);
        if (menu_index != 3'd0)
            $fatal(26, "empty review did not restore the default HOME menu");

        // Completing a quiz routes directly to summary.
        pulse(nav_select_pulse);
        expect_state(ST_LEARN, 27);
        pulse(nav_select_pulse);
        expect_state(ST_QUIZ, 27);
        answer_code = 2'd0;
        pulse(answer_valid);
        quiz_complete = 1'b1;
        acknowledge_feedback();
        quiz_complete = 1'b0;
        expect_state(ST_SUMMARY, 28);
        if (practice_next_change_pulse)
            $fatal(28, "quiz completion emitted a false next cue");

        // Reopening the completed quiz moves from summary back to its final
        // question and must therefore use the previous-page cue. Submitting
        // the replacement returns to summary without a false next cue.
        quiz_complete = 1'b1;
        pulse(nav_prev_pulse);
        if ((state != ST_QUIZ) || (page_index != 3'd2) ||
            !practice_prev_change_pulse || practice_next_change_pulse)
            $fatal(29, "summary reopen did not emit the previous cue");
        answer_code = 2'd1;
        pulse(answer_valid);
        expect_state(ST_FEEDBACK, 30);
        acknowledge_feedback();
        expect_state(ST_SUMMARY, 31);
        if (practice_next_change_pulse || practice_prev_change_pulse)
            $fatal(32, "summary edit return emitted a false cue");
        quiz_complete = 1'b0;

        // Corrupt state encoding must recover to HOME in one clock.
        @(negedge clk);
        dut.state = 4'hf;
        @(posedge clk);
        #1;
        expect_state(ST_HOME, 29);
        if (!safe_recovery_pulse)
            $fatal(30, "illegal state recovery was not reported");

        if (submit_count != 5)
            $fatal(31, "unexpected accepted-answer count %0d", submit_count);

        // KEY4's long event must return from every practice context.
        @(negedge clk);
        dut.state = ST_QUIZ;
        pulse(home_long_pulse);
        expect_state(ST_HOME, 32);
        @(negedge clk);
        dut.state = ST_FEEDBACK;
        pulse(home_long_pulse);
        expect_state(ST_HOME, 33);
        @(negedge clk);
        dut.state = ST_WRONG_REVIEW;
        pulse(home_long_pulse);
        expect_state(ST_HOME, 34);

        $display("TEST_PASS tb_learning_controller");
        $finish;
    end
endmodule
