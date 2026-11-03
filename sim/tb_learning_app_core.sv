`timescale 1ns/1ps

module tb_learning_app_core;
localparam [3:0] ST_HOME = 4'd1;
localparam [3:0] ST_LEARN = 4'd2;
localparam [3:0] ST_QUIZ = 4'd3;
localparam [3:0] ST_FEEDBACK = 4'd4;
localparam [3:0] ST_WRONG_REVIEW = 4'd5;
localparam [3:0] ST_SUMMARY = 4'd8;

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
wire [3:0] state;
wire [2:0] menu_index;
wire [2:0] page_index;
wire [3:0] image_index;
wire [3:0] page_number;
wire question_valid;
wire [2:0] question_type;
wire [7:0] prompt_token;
wire [7:0] option_a_token, option_b_token, option_c_token, option_d_token;
wire [1:0] expected_answer;
wire [1:0] difficulty;
wire music_quiz_audio_request;
wire answer_locked, answer_correct, quiz_complete;
wire [3:0] answered_count, correct_count;
wire [7:0] score_percent;
wire [1:0] star_level;
wire wrong_questions_available;
wire [3:0] wrong_count;
wire [2:0] wrong_bitmap;
wire [2:0] first_wrong_question;
wire answer_in_review, safe_recovery_pulse;
wire practice_prev_change_pulse, practice_next_change_pulse;
wire practice_prefetch_valid;
wire [3:0] practice_prefetch_image;
reg [3:0] prepared_first;
integer prefetch_guard;
reg [3:0] selected0, selected1, selected2;
reg [1:0] first_answer;
reg [1:0] second_answer;

always #5 clk = ~clk;

learning_app_core dut (
    .clk(clk), .rst(rst), .boot_done(boot_done),
    .content_ready(content_ready),
    .nav_next_pulse(nav_next_pulse), .nav_prev_pulse(nav_prev_pulse),
    .nav_select_pulse(nav_select_pulse),
    .nav_back_pulse(nav_back_pulse), .home_long_pulse(home_long_pulse),
    .answer_valid(answer_valid), .answer_code(answer_code),
    .feedback_ack_pressed(feedback_ack_pressed),
    .feedback_done(feedback_done), .state(state), .menu_index(menu_index),
    .page_index(page_index), .image_index(image_index),
    .page_number(page_number), .question_valid(question_valid),
    .question_type(question_type), .prompt_token(prompt_token),
    .option_a_token(option_a_token), .option_b_token(option_b_token),
    .option_c_token(option_c_token), .option_d_token(option_d_token),
    .expected_answer(expected_answer), .difficulty(difficulty),
    .music_quiz_audio_request(music_quiz_audio_request),
    .answer_locked(answer_locked), .answer_correct(answer_correct),
    .quiz_complete(quiz_complete), .answered_count(answered_count),
    .correct_count(correct_count), .score_percent(score_percent),
    .star_level(star_level),
    .wrong_questions_available(wrong_questions_available),
    .wrong_count(wrong_count), .wrong_question_bitmap(wrong_bitmap), .first_wrong_question(first_wrong_question),
    .answer_in_review(answer_in_review),
    .safe_recovery_pulse(safe_recovery_pulse),
    .practice_prev_change_pulse(practice_prev_change_pulse),
    .practice_next_change_pulse(practice_next_change_pulse),
    .practice_prefetch_valid(practice_prefetch_valid),
    .practice_prefetch_image(practice_prefetch_image)
);

task automatic pulse(ref reg signal);
    begin
        @(negedge clk); signal = 1'b1;
        @(negedge clk); signal = 1'b0; #1;
    end
endtask

task automatic submit_and_finish(input [1:0] answer);
    begin
        answer_code = answer;
        pulse(answer_valid);
        @(posedge clk); #1;
        if (state != ST_FEEDBACK || !answer_locked)
            $fatal(1, "answer did not enter locked feedback state");
        pulse(feedback_ack_pressed);
        pulse(feedback_done);
    end
endtask

initial begin
    repeat (3) @(posedge clk);
    @(negedge clk); rst = 1'b0;
    pulse(boot_done);
    if (state != ST_HOME) $fatal(2, "boot did not reach HOME");

    pulse(nav_select_pulse);
    if (state != ST_HOME || !safe_recovery_pulse)
        $fatal(3, "missing twelve-card package did not fail safely");

    content_ready = 1'b1;
    prefetch_guard = 0;
    while (!practice_prefetch_valid) begin
        @(negedge clk); prefetch_guard = prefetch_guard + 1;
        if (prefetch_guard > 20)
            $fatal(1, "HOME cache target was not prepared");
    end
    if (practice_prefetch_image < 3 || practice_prefetch_image > 5)
        $fatal(1, "HOME did not prepare a first-question target");
    pulse(nav_select_pulse);
    if (state != ST_LEARN || image_index != 4'd0 || page_number != 4'd1)
        $fatal(4, "first learning card metadata mismatch");
    pulse(nav_next_pulse);
    if (image_index != 4'd1 || page_number != 4'd2)
        $fatal(5, "second learning card mapping failed");
    pulse(nav_next_pulse);
    if (image_index != 4'd2 || page_number != 4'd3)
        $fatal(6, "three-card learning sequence did not reach final page");
    pulse(nav_prev_pulse);
    if (image_index != 4'd1 || page_number != 4'd2)
        $fatal(6, "learning previous did not return to the second card");
    pulse(nav_next_pulse);

    if (!practice_prefetch_valid || practice_prefetch_image < 3 ||
        practice_prefetch_image > 5)
        $fatal(1, "first question was not prepared during learning");
    prepared_first = practice_prefetch_image;
    pulse(nav_select_pulse);
    @(posedge clk); #1;
    selected0 = dut.selected_image0;
    selected1 = dut.selected_image1;
    selected2 = dut.selected_image2;
    if (state != ST_QUIZ || page_index != 3'd0 || !question_valid ||
        selected0 < 4'd3 || selected0 > 4'd5 ||
        selected1 < 4'd6 || selected1 > 4'd8 ||
        selected2 < 4'd9 || selected2 > 4'd11 ||
        image_index != selected0 || music_quiz_audio_request)
        $fatal(7, "random three-pool session was not latched correctly");
    if (selected0 != prepared_first || practice_prefetch_valid)
        $fatal(1, "quiz entry changed prepared first question or kept prefetch enabled");
    repeat (8) @(negedge clk);
    if (dut.selected_image0 != selected0 || dut.selected_image1 != selected1 ||
        dut.selected_image2 != selected2)
        $fatal(1, "preparing next session changed active quiz table");

    // Deliberately miss the first selected card, then answer the remaining
    // two from their live metadata. The selected image table must stay fixed.
    first_answer = expected_answer;
    submit_and_finish(expected_answer + 2'd1);
    if (state != ST_QUIZ || page_index != 3'd1 || image_index != selected1)
        $fatal(8, "quiz did not advance to the selected sentence card");
    pulse(nav_prev_pulse);
    if (page_index != 3'd0 || image_index != selected0)
        $fatal(8, "quiz previous did not restore the first selected card");
    submit_and_finish(first_answer);
    if (state != ST_QUIZ || page_index != 3'd1 || image_index != selected1 ||
        answered_count != 4'd1 || correct_count != 4'd1 ||
        wrong_questions_available)
        $fatal(8, "corrected first answer did not replace its old score");
    second_answer = expected_answer;
    submit_and_finish(expected_answer);
    if (state != ST_QUIZ || page_index != 3'd2 || image_index != selected2)
        $fatal(9, "quiz did not advance to the selected question card");
    pulse(nav_prev_pulse);
    if (page_index != 3'd1 || image_index != selected1)
        $fatal(9, "second quiz previous did not restore the sentence card");
    submit_and_finish(second_answer + 2'd1);
    if (state != ST_QUIZ || page_index != 3'd2 || image_index != selected2 ||
        answered_count != 4'd2 || correct_count != 4'd1 ||
        wrong_count != 4'd1 || first_wrong_question != 3'd1)
        $fatal(9, "revised wrong answer did not update score and wrong queue");
    submit_and_finish(expected_answer);

    if (!quiz_complete || state != ST_SUMMARY || answered_count != 4'd3 ||
        correct_count != 4'd2 || score_percent != 8'd66 ||
        wrong_count != 4'd1 || wrong_bitmap != 3'b010 || !wrong_questions_available ||
        first_wrong_question != 3'd1)
        $fatal(10, "three-question score or wrong queue mismatch");
    if (dut.selected_image0 != selected0 || dut.selected_image1 != selected1 ||
        dut.selected_image2 != selected2)
        $fatal(11, "selected questions changed during the session");

    // SUMMARY can reopen the completed quiz. Walk back from Q2 to Q1, submit
    // one replacement, then return directly to the refreshed summary.
    pulse(nav_prev_pulse);
    if (state != ST_QUIZ || page_index != 3'd2)
        $fatal(12, "summary did not reopen the final quiz question");
    pulse(nav_prev_pulse);
    if (page_index != 3'd1 || image_index != selected1)
        $fatal(12, "summary edit path did not walk back to question one");
    submit_and_finish(second_answer + 2'd1);
    if (state != ST_SUMMARY || wrong_count != 4'd1)
        $fatal(12, "summary edit did not return to the refreshed score");

    pulse(nav_select_pulse);
    if (state != ST_WRONG_REVIEW || image_index != selected1 ||
        expected_answer != second_answer)
        $fatal(12, "wrong review did not preserve the original selected card");

    answer_code = second_answer + 2'd1;
    pulse(answer_valid);
    @(posedge clk); #1;
    if (state != ST_FEEDBACK || !answer_in_review || answer_correct)
        $fatal(13, "wrong review retry did not enter feedback");
    pulse(feedback_ack_pressed);
    pulse(feedback_done);
    if (state != ST_WRONG_REVIEW || image_index != selected1 ||
        wrong_count != 4'd1)
        $fatal(14, "wrong review retry did not remain on the same card");

    answer_code = second_answer;
    pulse(answer_valid);
    @(posedge clk); #1;
    if (state != ST_FEEDBACK || !answer_in_review || !answer_correct)
        $fatal(15, "correct review answer was not accepted");
    pulse(feedback_ack_pressed);
    pulse(feedback_done);
    @(posedge clk); #1;
    if (state != ST_HOME || menu_index != 3'd0 ||
        wrong_questions_available || wrong_count != 4'd0 || wrong_bitmap != 0 ||
        answered_count != 4'd3 || correct_count != 4'd2)
        $fatal(16, "last correction did not return HOME with score preserved");
    repeat (8) @(posedge clk);
    #1;
    if (state != ST_HOME)
        $fatal(17, "completed review did not remain at HOME without extra input");

    // A second session begins while the previous selector output is still
    // valid.  During the controller's one-cycle session refresh, that stale
    // card must be marked invalid so the top-level image mailbox cannot issue
    // a first request and then a second request for the new random card.
    pulse(nav_select_pulse);
    if (state != ST_LEARN || answered_count != 4'd3 ||
        dut.session_clear_pulse)
        $fatal(1, "HOME entry unexpectedly started a new exercise session");
    pulse(nav_select_pulse);
    if (state != ST_QUIZ || question_valid)
        $fatal(18, "stale first exercise card remained requestable during refresh");
    @(posedge clk); #1;
    if (!question_valid || image_index < 4'd3 || image_index > 4'd5)
        $fatal(19, "new first exercise card did not become valid atomically");

    $display("TEST_PASS tb_learning_app_core selected=%0d/%0d/%0d",
             selected0, selected1, selected2);
    $finish;
end
endmodule
