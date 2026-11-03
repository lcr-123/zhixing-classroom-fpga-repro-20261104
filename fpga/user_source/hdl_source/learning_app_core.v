`timescale 1ns/1ps

// Single-subject English nature application. Three learning pages are fixed;
// each quiz session latches one exercise from each of three independent pools.
// The wrong-question bitmap stores quiz slots, while the selected image table
// remains unchanged through review so a retry always shows the original card.
module learning_app_core (
    input  wire        clk,
    input  wire        rst,
    input  wire        boot_done,
    input  wire        content_ready,
    input  wire        nav_next_pulse,
    input  wire        nav_prev_pulse,
    input  wire        nav_select_pulse,
    input  wire        nav_back_pulse,
    input  wire        home_long_pulse,
    input  wire        answer_valid,
    input  wire [1:0]  answer_code,
    input  wire        feedback_ack_pressed,
    input  wire        feedback_done,
    output wire [3:0]  state,
    output wire [2:0]  menu_index,
    output wire [2:0]  page_index,
    output wire [3:0]  image_index,
    output wire [3:0]  page_number,
    output wire        question_valid,
    output wire [2:0]  question_type,
    output wire [7:0]  prompt_token,
    output wire [7:0]  option_a_token,
    output wire [7:0]  option_b_token,
    output wire [7:0]  option_c_token,
    output wire [7:0]  option_d_token,
    output wire [1:0]  expected_answer,
    output wire [1:0]  difficulty,
    output wire        music_quiz_audio_request,
    output wire        answer_locked,
    output wire        answer_correct,
    output wire        quiz_complete,
    output wire [3:0]  answered_count,
    output wire [3:0]  correct_count,
    output wire [7:0]  score_percent,
    output wire [1:0]  star_level,
    output wire        wrong_questions_available,
    output wire [3:0]  wrong_count,
    output wire [2:0]  wrong_question_bitmap,
    output wire [2:0]  first_wrong_question,
    output wire        answer_in_review,
    output wire        safe_recovery_pulse,
    output wire        practice_prev_change_pulse,
    output wire        practice_next_change_pulse,
    output wire        practice_prefetch_valid,
    output wire [3:0]  practice_prefetch_image
);

localparam [3:0] ST_QUIZ         = 4'd3;
localparam [3:0] ST_FEEDBACK     = 4'd4;
localparam [3:0] ST_WRONG_REVIEW = 4'd5;

wire [1:0] selected_answer;
wire answer_in_review_i;
wire answer_submit_pulse;
wire answer_reopen_pulse;
wire session_clear_pulse;
wire quiz_complete_i;
wire [3:0] answered_count_i;
wire [3:0] correct_count_i;
wire [7:0] score_percent_i;
wire [1:0] star_level_i;
wire [2:0] wrong_bitmap;
assign wrong_question_bitmap = wrong_bitmap;
wire mark_wrong_pulse;
wire mark_correct_pulse;
wire review_context = (state == ST_WRONG_REVIEW) ||
                      ((state == ST_FEEDBACK) && answer_in_review_i);
reg [2:0] review_feedback_slot;
wire [2:0] active_question_slot = review_context ?
    ((state == ST_FEEDBACK) ? review_feedback_slot : first_wrong_question) :
    page_index;

// Clearing a corrected queue entry immediately advances (or empties) its
// cursor. Keep the submitted card and metadata throughout feedback instead
// of requesting the next/default card before the learner acknowledges it.
always @(posedge clk) begin
    if (rst || session_clear_pulse)
        review_feedback_slot <= 3'd0;
    else if (state == ST_WRONG_REVIEW)
        review_feedback_slot <= first_wrong_question;
end

reg [15:0] entropy_counter;
wire selection_valid;
wire selection_fault;
wire [3:0] prepared_image0;
wire [3:0] prepared_image1;
wire [3:0] prepared_image2;
reg [3:0] selected_image0;
reg [3:0] selected_image1;
reg [3:0] selected_image2;
reg active_selection_valid;
reg prepare_pending;
wire prepare_start = prepare_pending && content_ready;
// Prepare the NEXT session without changing the current quiz/review table.
// The first selection is available while HOME is displayed. After accepting
// it, prepare another table; only HOME/LEARN may request its background read.
always @(posedge clk) begin
    if (rst) begin
        prepare_pending <= 1'b1;
        active_selection_valid <= 1'b0;
        selected_image0 <= 4'd3;
        selected_image1 <= 4'd6;
        selected_image2 <= 4'd9;
    end else begin
        if (prepare_start)
            prepare_pending <= 1'b0;
        if (session_clear_pulse) begin
            selected_image0 <= prepared_image0;
            selected_image1 <= prepared_image1;
            selected_image2 <= prepared_image2;
            active_selection_valid <= selection_valid && !selection_fault;
            prepare_pending <= 1'b1;
        end
    end
end
assign practice_prefetch_valid = content_ready && selection_valid &&
    !selection_fault && !prepare_pending &&
    ((state == 4'd1) || (state == 4'd2));
// Keep the next quiz target stable in HOME and LEARN. The SD scheduler first
// warms the shared entry card before using the independent quiz buffer.
assign practice_prefetch_image = prepared_image0;
reg [3:0] active_question_image;

wire metadata_valid;
wire [1:0] metadata_group;
wire [7:0] metadata_prompt;
wire [7:0] metadata_option_a;
wire [7:0] metadata_option_b;
wire [7:0] metadata_option_c;
wire [7:0] metadata_option_d;
wire [1:0] metadata_answer;
wire [1:0] metadata_difficulty;
wire course_card_valid;
wire course_question_page;
wire [1:0] course_question_group;
wire [1:0] course_correct_answer;

always @(posedge clk) begin
    if (rst)
        entropy_counter <= 16'h5A3C;
    else
        entropy_counter <= entropy_counter + 16'd1;
end

always @* begin
    case (active_question_slot)
        3'd0: active_question_image = selected_image0;
        3'd1: active_question_image = selected_image1;
        3'd2: active_question_image = selected_image2;
        default: active_question_image = 4'd3;
    endcase
end

learning_controller u_controller (
    .clk(clk), .rst(rst), .boot_done(boot_done),
    .content_ready(content_ready),
    .nav_next_pulse(nav_next_pulse), .nav_prev_pulse(nav_prev_pulse),
    .nav_select_pulse(nav_select_pulse),
    .nav_back_pulse(nav_back_pulse), .home_long_pulse(home_long_pulse),
    .answer_valid(answer_valid), .answer_code(answer_code),
    .feedback_ack_pressed(feedback_ack_pressed),
    .feedback_done(feedback_done), .quiz_complete(quiz_complete_i),
    .wrong_questions_available(wrong_questions_available),
    .page_count(3'd3), .state(state), .menu_index(menu_index),
    .page_index(page_index), .selected_answer(selected_answer),
    .answer_in_review(answer_in_review_i),
    .answer_submit_pulse(answer_submit_pulse),
    .answer_reopen_pulse(answer_reopen_pulse),
    .session_clear_pulse(session_clear_pulse),
    .safe_recovery_pulse(safe_recovery_pulse),
    .practice_prev_change_pulse(practice_prev_change_pulse),
    .practice_next_change_pulse(practice_next_change_pulse)
);

random_three_question_selector u_random_questions (
    .clk(clk), .rst(rst), .session_start(prepare_start),
    .entropy_counter(entropy_counter),
    .vocabulary_count(content_ready ? 2'd3 : 2'd0),
    .sentence_count(content_ready ? 2'd3 : 2'd0),
    .question_count(content_ready ? 2'd3 : 2'd0),
    .selection_valid(selection_valid), .selection_fault(selection_fault),
    .question_image0(prepared_image0), .question_image1(prepared_image1),
    .question_image2(prepared_image2)
);

english_nature_question_rom u_question_rom (
    .image_index(active_question_image),
    .question_valid(metadata_valid), .question_group(metadata_group),
    .prompt_token(metadata_prompt), .option_a_token(metadata_option_a),
    .option_b_token(metadata_option_b), .option_c_token(metadata_option_c),
    .option_d_token(metadata_option_d), .correct_answer(metadata_answer),
    .difficulty(metadata_difficulty)
);

english_nature_course_rom u_course_rom (
    .image_index(active_question_image),
    .available_count(content_ready ? 4'd12 : 4'd0),
    .card_valid(course_card_valid), .safe_home_request(),
    .learning_page(), .question_page(course_question_page),
    .question_group(course_question_group), .group_index(),
    .correct_answer(course_correct_answer), .expected_width(),
    .expected_height()
);

quiz_engine #(.QUESTION_COUNT(3)) u_quiz_engine (
    .clk(clk), .rst(rst), .session_clear(session_clear_pulse),
    .submit_valid(answer_submit_pulse),
    .feedback_done(feedback_done | answer_reopen_pulse),
    .review_mode(answer_in_review_i), .question_index(active_question_slot),
    .selected_answer(selected_answer), .expected_answer(course_correct_answer),
    .question_count(3'd3), .submit_accepted(),
    .answer_correct(answer_correct), .answer_locked(answer_locked),
    .mark_wrong_pulse(mark_wrong_pulse),
    .mark_correct_pulse(mark_correct_pulse),
    .quiz_complete(quiz_complete_i), .answered_count(answered_count_i),
    .correct_count(correct_count_i), .current_streak(), .max_streak(),
    .score_percent(score_percent_i), .star_level(star_level_i),
    .answered_bitmap()
);

wrong_question_queue #(.QUESTION_COUNT(3)) u_wrong_queue (
    .clk(clk), .rst(rst), .clear_all(session_clear_pulse),
    .set_wrong(mark_wrong_pulse), .clear_wrong(mark_correct_pulse),
    .question_index(active_question_slot), .wrong_bitmap(wrong_bitmap),
    .wrong_count(wrong_count), .wrong_available(wrong_questions_available),
    .first_wrong_question(first_wrong_question)
);

assign image_index = ((state == ST_QUIZ) || (state == ST_FEEDBACK) ||
                      (state == ST_WRONG_REVIEW)) ?
                     active_question_image : {1'b0, page_index};
assign page_number = image_index + 4'd1;
// Suppress the previous session's still-valid selection during the one-cycle
// session refresh. The prepared table is latched on the following edge, so
// exposing the old card here would allow the image request
// mailbox to queue it immediately before the newly selected card.
assign question_valid = content_ready && !session_clear_pulse && active_selection_valid &&
                        metadata_valid &&
                        course_card_valid && course_question_page &&
                        (metadata_group == course_question_group) &&
                        (metadata_answer == course_correct_answer);
assign question_type = {1'b0, course_question_group};
assign prompt_token = metadata_prompt;
assign option_a_token = metadata_option_a;
assign option_b_token = metadata_option_b;
assign option_c_token = metadata_option_c;
assign option_d_token = metadata_option_d;
assign expected_answer = course_correct_answer;
assign difficulty = metadata_difficulty;
assign music_quiz_audio_request = 1'b0;
assign answer_in_review = answer_in_review_i;
assign quiz_complete = quiz_complete_i;
assign answered_count = answered_count_i;
assign correct_count = correct_count_i;
assign score_percent = score_percent_i;
assign star_level = star_level_i;

endmodule
