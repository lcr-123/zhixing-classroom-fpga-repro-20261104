`timescale 1ns/1ps
// Real app/queue, production top image/HOME publishers and SD loader. Media
// payload is the shared fixture; every load, write completion and commit is
// counted so a correct state value cannot conceal an intermediate image.
module tb_review_feedback_image;
localparam APP_ST_BOOT_SELFTEST=0, APP_ST_HOME=1, APP_ST_LEARN=2,
           APP_ST_QUIZ=3, APP_ST_FEEDBACK=4, APP_ST_WRONG_REVIEW=5,
           APP_ST_SOUND_LAB=6, APP_ST_SETTINGS=7, APP_ST_SUMMARY=8;
reg clk=0, rst_ref=1, boot_done=0;
always #10 clk=~clk;
reg nav_next=0, nav_select=0, answer_valid=0, feedback_ack=0, feedback_done=0;
reg [1:0] answer_code=0;
wire [3:0] learn_state, learn_image_index;
wire [1:0] expected_answer;
wire learn_question_valid, practice_prev_change_event;
wire sound_quiz_active=1'b0;
wire [2:0] wrong_bitmap;
reg home_request_toggle_ref, home_state_active_ref;
reg [2:0] home_request_toggle_sd_sync=0;
wire sd_home_request, sd_app_image_request;
wire app_image_context_active;
wire [3:0] app_desired_image_index;
wire [2:0] app_desired_zoom_level=3'd2;
reg [3:0] app_image_mailbox_ref;
reg [2:0] app_image_zoom_mailbox_ref;
reg app_image_prev_mailbox_ref, app_image_settings_mailbox_ref;
reg app_image_request_toggle_ref, app_image_context_active_ref;
reg [2:0] app_image_request_toggle_sd_sync=0;
reg [3:0] app_image_index_sd_meta=0, app_image_index_sd_sync=0;
reg [2:0] app_image_zoom_sd_meta=2, app_image_zoom_sd_sync=2;
reg [3:0] learn_state_sd_sync1=0, learn_state_sd_sync2=0;
reg image_prev_meta=0, image_prev_sync=0, settings_meta=0, settings_sync=0;
integer image_requests=0, home_requests=0, commits=0, completed_load=0;
integer i, run_index, mask, q, before_req, before_home, before_load, before_commit;
reg [3:0] held_image;
reg [1:0] held_answer;
reg complete_frames=1, commit_seen=0;
reg [3:0] committed_images[0:255];

`include "out/review_feedback_image/routes.vh"

learning_app_core app (
    .clk(clk), .rst(rst_ref), .boot_done(boot_done), .content_ready(1'b1),
    .nav_next_pulse(nav_next), .nav_prev_pulse(1'b0),
    .nav_select_pulse(nav_select), .nav_back_pulse(1'b0), .home_long_pulse(1'b0),
    .answer_valid(answer_valid), .answer_code(answer_code),
    .feedback_ack_pressed(feedback_ack), .feedback_done(feedback_done),
    .state(learn_state), .image_index(learn_image_index),
    .expected_answer(expected_answer), .question_valid(learn_question_valid),
    .wrong_question_bitmap(wrong_bitmap),
    .practice_prev_change_pulse(practice_prev_change_event),
    .menu_index(), .page_index(), .page_number(), .question_type(),
    .prompt_token(), .option_a_token(), .option_b_token(), .option_c_token(),
    .option_d_token(), .difficulty(), .music_quiz_audio_request(),
    .answer_locked(), .answer_correct(), .quiz_complete(), .answered_count(),
    .correct_count(), .score_percent(), .star_level(),
    .wrong_questions_available(), .wrong_count(), .first_wrong_question(),
    .answer_in_review(), .safe_recovery_pulse(), .practice_next_change_pulse()
);
tb_sd_card_bmp_control #(.HOME_TEST(1)) fixture();

// The same three-toggle/two-data stages as the production SD crossing.
always @(posedge fixture.clk) begin
    if (fixture.rst) begin
        home_request_toggle_sd_sync<=0;
        app_image_request_toggle_sd_sync<=0;
        app_image_index_sd_meta<=0; app_image_index_sd_sync<=0;
        app_image_zoom_sd_meta<=2; app_image_zoom_sd_sync<=2;
        learn_state_sd_sync1<=0; learn_state_sd_sync2<=0;
        image_prev_meta<=0; image_prev_sync<=0;
        settings_meta<=0; settings_sync<=0;
    end else begin
        home_request_toggle_sd_sync<=
            {home_request_toggle_sd_sync[1:0],home_request_toggle_ref};
        app_image_request_toggle_sd_sync<=
            {app_image_request_toggle_sd_sync[1:0],app_image_request_toggle_ref};
        app_image_index_sd_meta<=app_image_mailbox_ref;
        app_image_index_sd_sync<=app_image_index_sd_meta;
        app_image_zoom_sd_meta<=app_image_zoom_mailbox_ref;
        app_image_zoom_sd_sync<=app_image_zoom_sd_meta;
        learn_state_sd_sync1<=learn_state;
        learn_state_sd_sync2<=learn_state_sd_sync1;
        image_prev_meta<=app_image_prev_mailbox_ref;
        image_prev_sync<=image_prev_meta;
        settings_meta<=app_image_settings_mailbox_ref;
        settings_sync<=settings_meta;
    end
end
always @(negedge fixture.clk) begin
    fixture.home_request=sd_home_request;
    fixture.image_request=sd_app_image_request;
    fixture.image_request_idx=app_image_index_sd_sync;
    fixture.image_request_zoom=app_image_zoom_sd_sync;
    fixture.image_request_prev=image_prev_sync;
    fixture.image_request_settings=settings_sync;
    if (sd_home_request) home_requests=home_requests+1;
    if (sd_app_image_request) begin
        image_requests=image_requests+1;
        $display("IMAGE_REQUEST state=%0d slot=%0d",learn_state,app_image_index_sd_sync);
    end
    if (complete_frames && fixture.dut.source_done_seen &&
        completed_load!=fixture.load_count) begin
        fixture.write_finish_toggle=~fixture.write_finish_toggle;
        completed_load=fixture.load_count;
    end
    if (fixture.display_commit_toggle!=commit_seen) begin
        commit_seen=fixture.display_commit_toggle;
        committed_images[commits]=fixture.display_image_idx;
        commits=commits+1;
        $display("IMAGE_COMMIT slot=%0d",fixture.display_image_idx);
    end
    if (complete_frames)
        fixture.display_commit_ack_toggle=fixture.display_commit_toggle;
end

task automatic pulse(ref reg signal);
begin @(negedge clk); signal=1; @(negedge clk); signal=0; #1; end
endtask
task automatic settle;
begin repeat(100) @(negedge clk); end
endtask
task automatic acknowledge;
begin pulse(feedback_ack); pulse(feedback_done); end
endtask
task automatic snapshot;
begin
    held_image=learn_image_index; held_answer=expected_answer;
    before_req=image_requests; before_home=home_requests;
    before_load=fixture.load_count; before_commit=commits;
end
endtask
task automatic check_feedback_hold;
begin
    if (learn_state!=APP_ST_FEEDBACK || learn_image_index!=held_image ||
        expected_answer!=held_answer || image_requests!=before_req ||
        home_requests!=before_home || fixture.load_count!=before_load ||
        commits!=before_commit)
        $fatal(1,"FEEDBACK_IMAGE_CHANGED mask=%0d q=%0d held=%0d got=%0d request/load/commit delta=%0d/%0d/%0d",
            mask,q,held_image,learn_image_index,image_requests-before_req,
            fixture.load_count-before_load,commits-before_commit);
end
endtask

initial begin
    repeat(4) @(negedge fixture.clk);
    fixture.rst=0; fixture.dut.sd_card_top_m0.sd_init_done=1;
    fixture.dut.bmp_read_m0.ready=1;
    wait(fixture.dut.scan_start_pulse);
    fixture.dut.u_fat32_volume_scanner.state=0;
    fixture.dut.bmp_read_m0.ready=0;
    for(i=0;i<13;i=i+1) fixture.report_found(i);
    fixture.finish_scan(); fixture.dut.bmp_read_m0.ready=1;
    settle();
    @(negedge clk); rst_ref=0; pulse(boot_done); settle();
    if (learn_state!=APP_ST_HOME || fixture.display_image_idx!=12)
        $fatal(1,"boot cover missing");

    // Start with only the last question wrong: the old implementation would
    // load selected_image0 during its final feedback, before HOME is pressed.
    for(run_index=0;run_index<7;run_index=run_index+1) begin
        mask=(run_index==0) ? 4 : ((run_index<4) ? run_index : run_index+1);
        pulse(nav_select); pulse(nav_select); settle();
        for(q=0;q<3;q=q+1) begin
            if (learn_state!=APP_ST_QUIZ) $fatal(1,"primary quiz not ready");
            answer_code=expected_answer+((mask & (1<<q)) ? 2'd1 : 2'd0);
            pulse(answer_valid); settle(); acknowledge(); settle();
        end
        if (learn_state!=APP_ST_SUMMARY || wrong_bitmap!=mask)
            $fatal(1,"primary summary/bitmap changed");
        pulse(nav_select); settle();
        for(q=0;q<3;q=q+1) if (mask & (1<<q)) begin
            if (learn_state!=APP_ST_WRONG_REVIEW)
                $fatal(1,"review not ready");
            snapshot();
            answer_code=held_answer+2'd1;
            pulse(answer_valid); settle(); check_feedback_hold();
            acknowledge(); settle();
            if (learn_state!=APP_ST_WRONG_REVIEW || learn_image_index!=held_image)
                $fatal(1,"wrong retry left current card");
            snapshot(); answer_code=held_answer;
            pulse(answer_valid); settle(); check_feedback_hold();
            // Holding the feedback, extra answers and an unarmed completion
            // cannot change its picture or issue speculative loads.
            pulse(answer_valid); pulse(feedback_done); settle();
            check_feedback_hold();
            if (wrong_bitmap!=(mask & ~((1<<(q+1))-1)))
                $fatal(1,"wrong queue did not clear exactly the answered slot");
            acknowledge(); settle();
            if ((mask >> (q+1))==0) begin
                if (learn_state!=APP_ST_HOME || fixture.display_image_idx!=12 ||
                    home_requests!=before_home+1 || image_requests!=before_req ||
                    fixture.load_count!=before_load+1 || commits!=before_commit+1 ||
                    committed_images[before_commit]!=12)
                    $fatal(1,"final ACK displayed an intermediate picture");
            end else if (learn_state!=APP_ST_WRONG_REVIEW ||
                         image_requests!=before_req+1 || commits!=before_commit+1)
                $fatal(1,"next wrong card must load only after ACK");
        end
        $display("REVIEW_IMAGE_MASK_PASS %0d",mask);
    end

    // Busy writer: hold the final review card's legitimate load across its
    // correction and HOME entry. Only that card then the cover may commit.
    mask=6; pulse(nav_select); pulse(nav_select); settle();
    for(q=0;q<3;q=q+1) begin
        answer_code=expected_answer+((q==0)?2'd0:2'd1);
        pulse(answer_valid); settle(); acknowledge(); settle();
    end
    pulse(nav_select); settle();
    answer_code=expected_answer; pulse(answer_valid); settle();
    complete_frames=0; acknowledge(); settle();
    wait(fixture.dut.source_done_seen);
    snapshot(); answer_code=held_answer; pulse(answer_valid); settle();
    check_feedback_hold(); acknowledge(); settle();
    if (learn_state!=APP_ST_HOME || home_requests!=before_home+1 ||
        image_requests!=before_req || fixture.load_count!=before_load ||
        commits!=before_commit || !fixture.dut.home_req_pending)
        $fatal(1,"busy HOME request/held write not preserved");
    complete_frames=1; settle();
    if (fixture.display_image_idx!=12 || commits!=before_commit+2 ||
        committed_images[before_commit]!=held_image ||
        committed_images[before_commit+1]!=12 || fixture.load_count!=before_load+1)
        $fatal(1,"busy HOME committed an unrelated card");

    // Reset while a corrected review is waiting for feedback confirmation.
    pulse(nav_select); pulse(nav_select); settle();
    for(q=0;q<3;q=q+1) begin
        answer_code=expected_answer+((q==2)?2'd1:2'd0);
        pulse(answer_valid); settle(); acknowledge(); settle();
    end
    pulse(nav_select); settle();
    answer_code=expected_answer; pulse(answer_valid); settle();
    @(negedge clk); rst_ref=1; settle();
    @(negedge clk); rst_ref=0; pulse(boot_done); settle();
    if (learn_state!=APP_ST_HOME || wrong_bitmap!=0 || fixture.display_image_idx!=12)
        $fatal(1,"feedback reset failed safe HOME recovery");
    $display("TEST_PASS review feedback images: 7 wrong masks, retries, ACK hold, real mailboxes/load/commit, busy HOME, reset");
    $finish;
end
initial begin #2000000; $fatal(1,"review feedback image timeout"); end
endmodule
