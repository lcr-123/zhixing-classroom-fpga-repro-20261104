`timescale 1ns/1ps
// Actual app/queue and production HOME toggle, with the shared media/writer
// fixture. Prove the cover request, not just the controller state value.
module tb_review_home;
localparam APP_ST_HOME=1, APP_ST_BOOT_SELFTEST=0;
reg clk=0, rst_ref=1, boot_done=0;
always #10 clk=~clk;
reg nav_next=0, nav_select=0, answer_valid=0, feedback_ack=0, feedback_done=0;
reg [1:0] answer_code=0;
wire [3:0] learn_state, wrong_count;
wire [1:0] expected_answer;
wire [2:0] menu_index;
wire wrong_available;
reg home_request_toggle_ref, home_state_active_ref;
reg [2:0] home_request_toggle_sd_sync=0;
wire sd_home_request;
integer home_requests=0, i, before_requests, before_load;
reg [3:0] review_image;

`include "out/review_home/home_route.vh"

learning_app_core app (
    .clk(clk), .rst(rst_ref), .boot_done(boot_done), .content_ready(1'b1),
    .nav_next_pulse(nav_next), .nav_prev_pulse(1'b0),
    .nav_select_pulse(nav_select), .nav_back_pulse(1'b0), .home_long_pulse(1'b0),
    .answer_valid(answer_valid), .answer_code(answer_code),
    .feedback_ack_pressed(feedback_ack), .feedback_done(feedback_done),
    .state(learn_state), .menu_index(menu_index), .expected_answer(expected_answer),
    .wrong_questions_available(wrong_available), .wrong_count(wrong_count),
    .wrong_question_bitmap(),
    .page_index(), .image_index(), .page_number(), .question_valid(),
    .question_type(), .prompt_token(), .option_a_token(), .option_b_token(),
    .option_c_token(), .option_d_token(), .difficulty(), .music_quiz_audio_request(),
    .answer_locked(), .answer_correct(), .quiz_complete(), .answered_count(),
    .correct_count(), .score_percent(), .star_level(), .first_wrong_question(),
    .answer_in_review(), .safe_recovery_pulse(), .practice_prev_change_pulse(),
    .practice_next_change_pulse()
);
tb_sd_card_bmp_control #(.HOME_TEST(1)) fixture();

always @(posedge fixture.clk) begin
    if (fixture.rst) home_request_toggle_sd_sync<=0;
    else home_request_toggle_sd_sync<=
        {home_request_toggle_sd_sync[1:0],home_request_toggle_ref};
end
always @(negedge fixture.clk) begin
    fixture.home_request=sd_home_request;
    if (sd_home_request) home_requests=home_requests+1;
end

task automatic pulse(ref reg signal);
begin
    @(negedge clk); signal=1;
    @(negedge clk); signal=0; #1;
end
endtask
task automatic ack_feedback;
begin pulse(feedback_ack); pulse(feedback_done); end
endtask
task automatic answer(input integer correct);
begin
    answer_code=correct ? expected_answer : expected_answer+2'd1;
    pulse(answer_valid); repeat(4) @(negedge clk);
    if (learn_state!=4) $fatal(1,"answer did not enter feedback");
end
endtask
task automatic commit_frame(input [3:0] expected_index);
reg old_commit;
begin
    wait(fixture.dut.source_done_seen);
    repeat(5) @(negedge fixture.clk);
    old_commit=fixture.display_commit_toggle;
    fixture.write_finish_toggle=~fixture.write_finish_toggle;
    wait(fixture.display_commit_toggle!=old_commit); #1;
    if (!fixture.display_valid || fixture.display_image_idx!=expected_index)
        $fatal(1,"wrong complete frame committed expected=%0d got=%0d",
               expected_index,fixture.display_image_idx);
    fixture.display_commit_ack_toggle=fixture.display_commit_toggle;
    wait(!fixture.dut.display_commit_pending);
end
endtask

initial begin
    repeat(4) @(negedge fixture.clk);
    fixture.rst=0;
    fixture.dut.sd_card_top_m0.sd_init_done=1;
    fixture.dut.bmp_read_m0.ready=1;
    wait(fixture.dut.scan_start_pulse);
    fixture.dut.u_fat32_volume_scanner.state=0;
    fixture.dut.bmp_read_m0.ready=0;
    for(i=0;i<13;i=i+1) fixture.report_found(i);
    fixture.finish_scan(); fixture.dut.bmp_read_m0.ready=1;
    wait(fixture.load_count==1); commit_frame(12);
    @(negedge clk); rst_ref=0;
    pulse(boot_done);
    repeat(10) @(negedge clk);
    if (learn_state!=1 || home_requests!=1)
        $fatal(1,"boot HOME entry did not emit exactly one request");

    pulse(nav_select); pulse(nav_select);
    repeat(4) @(negedge clk);
    answer(0); ack_feedback();
    answer(0); ack_feedback();
    answer(0); ack_feedback();
    if (learn_state!=8 || wrong_count!=3)
        $fatal(1,"quiz did not retain score and wrong review entry");
    pulse(nav_select);
    if (learn_state!=5) $fatal(1,"cannot start wrong review");
    answer(0); ack_feedback();
    if (learn_state!=5 || wrong_count!=3 || home_requests!=1)
        $fatal(1,"wrong retry returned HOME prematurely");
    answer(1); ack_feedback();
    if (learn_state!=5 || wrong_count!=2 || home_requests!=1)
        $fatal(1,"first correction skipped remaining wrong questions");
    answer(1); ack_feedback();
    if (learn_state!=5 || wrong_count!=1 || home_requests!=1)
        $fatal(1,"second correction skipped remaining wrong question");

    // Hold a real exercise write unfinished across the last correction.
    @(negedge fixture.clk);
    review_image=app.image_index;
    fixture.image_request_idx=review_image; fixture.image_request=1;
    @(negedge fixture.clk); fixture.image_request=0;
    wait(fixture.load_count==2);
    wait(fixture.dut.source_done_seen);
    before_requests=home_requests; before_load=fixture.load_count;
    answer(1);
    repeat(6) @(negedge clk);
    if (wrong_available || learn_state!=4 || home_requests!=before_requests)
        $fatal(1,"last correction skipped feedback acknowledgement");
    pulse(feedback_done); // stale/unarmed event must not return HOME
    if (learn_state!=4) $fatal(1,"unarmed feedback event returned HOME");
    ack_feedback();
    repeat(12) @(negedge clk);
    if (learn_state!=1 || menu_index!=0 || home_requests!=before_requests+1 ||
        fixture.load_count!=before_load || fixture.display_image_idx!=12)
        $fatal(1,"HOME request was lost/repeated or exposed incomplete write");
    commit_frame(review_image);
    wait(fixture.load_count==before_load+1);
    if (fixture.dut.load_idx!=12 || fixture.dut.write_buf_idx==fixture.dut.disp_buf_idx)
        $fatal(1,"queued HOME did not target inactive cover buffer");
    commit_frame(12);
    repeat(30) @(negedge clk);
    if (home_requests!=before_requests+1 || fixture.load_count!=before_load+1 ||
        fixture.display_image_idx!=12 || learn_state!=1)
        $fatal(1,"idle HOME repeated request or lost cover");

    // A fresh practice must clear the old queue, and reset must discard a
    // previous HOME level before emitting the next boot entry once.
    pulse(nav_select); pulse(nav_select); repeat(4) @(negedge clk);
    if (learn_state!=3 || wrong_available) $fatal(1,"new practice inherited queue");
    @(negedge clk); rst_ref=1;
    repeat(3) @(negedge clk);
    rst_ref=0; pulse(boot_done); repeat(12) @(negedge clk);
    if (learn_state!=1 || fixture.display_image_idx!=12)
        $fatal(1,"reset recovery did not restore HOME");
    $display("TEST_PASS review HOME: actual app/queue/top toggle, wrong retry, ACK, busy writer, one cover load, reset");
    $finish;
end
initial begin #2000000; $fatal(1,"review HOME timeout"); end
endmodule
