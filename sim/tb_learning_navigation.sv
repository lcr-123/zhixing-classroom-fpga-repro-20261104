`timescale 1ns/1ps

// Actual top-level event routes + controller + actual image mailbox + loader.
// SD media/BMP payload are stubbed by the shared loader fixture; frame writer
// completion and display ACK remain explicit, independently delayed handshakes.
module tb_learning_navigation;
    localparam APP_ST_BOOT_SELFTEST=0, APP_ST_HOME=1, APP_ST_LEARN=2,
               APP_ST_QUIZ=3, APP_ST_FEEDBACK=4, APP_ST_SUMMARY=8,
               APP_ST_SETTINGS=7, APP_ST_SOUND_LAB=6;
    reg clk=0, rst_ref=1, boot_done=0, select_event=0;
    reg [1:0] learn_key_short=0, learn_key_long=0;
    reg lesson_volume_adjust_active=0, lesson_speed_adjust_active=0;
    reg [1:0] settings_edit_parameter=0;
    reg learn_answer_in_review=0, lesson_auto_next_event=0;
    wire [3:0] learn_state;
    wire [2:0] page_index;
    wire practice_double_click_active, learning_double_click_active;
    wire settings_zoom_navigation, key2_single_event;
    wire practice_key2_single, practice_key2_double;
    wire nav_next_event, nav_prev_event, home_long_event;
    wire practice_prev_change_event;
    wire app_image_context_active = learn_state == APP_ST_LEARN ||
                                    learn_state == APP_ST_SETTINGS;
    wire [3:0] app_desired_image_index =
        (learn_state == APP_ST_SETTINGS) ? 4'd0 : {1'b0,page_index};
    wire [2:0] app_desired_zoom_level =
        (app_desired_image_index == 0) ? 3'd4 :
        (app_desired_image_index == 1) ? 3'd1 : 3'd3;
    reg [3:0] app_image_mailbox_ref;
    reg [2:0] app_image_zoom_mailbox_ref;
    reg app_image_prev_mailbox_ref, app_image_request_toggle_ref;
    reg app_image_settings_mailbox_ref;
    reg app_image_context_active_ref;
    reg [2:0] request_sync=0;
    reg [3:0] index_meta=0, index_sync=0;
    reg [2:0] zoom_meta=2, zoom_sync=2;
    reg prev_meta=0, prev_sync=0;
    reg settings_meta=0, settings_sync=0;
    integer requests=0, commits=0, index, before_req, before_load, before_commit;
    integer completed_load=-1;
    reg complete_frames=1, commit_seen=0;

    always #10 clk=~clk;
    `include "out/learning_navigation/top_routes.vh"

    learning_controller controller (
        .clk(clk), .rst(rst_ref), .boot_done(boot_done), .content_ready(1'b1),
        .nav_next_pulse(nav_next_event | lesson_auto_next_event),
        .nav_prev_pulse(nav_prev_event), .nav_select_pulse(select_event),
        .nav_back_pulse(1'b0), .home_long_pulse(home_long_event),
        .answer_valid(1'b0), .answer_code(2'd0),
        .feedback_ack_pressed(1'b0), .feedback_done(1'b0),
        .quiz_complete(1'b0), .wrong_questions_available(1'b0),
        .page_count(3'd3), .state(learn_state), .page_index(page_index),
        .practice_prev_change_pulse(practice_prev_change_event),
        .menu_index(), .selected_answer(), .answer_in_review(),
        .answer_submit_pulse(), .answer_reopen_pulse(), .session_clear_pulse(),
        .safe_recovery_pulse(), .practice_next_change_pulse()
    );
    tb_sd_card_bmp_control #(.HOME_TEST(1)) fixture();

    // Same toggle/data synchronizer depths as the production SD mailbox.
    always @(posedge fixture.clk) begin
        request_sync <= {request_sync[1:0],app_image_request_toggle_ref};
        index_meta <= app_image_mailbox_ref;
        index_sync <= index_meta;
        zoom_meta <= app_image_zoom_mailbox_ref;
        zoom_sync <= zoom_meta;
        prev_meta <= app_image_prev_mailbox_ref;
        prev_sync <= prev_meta;
        settings_meta <= app_image_settings_mailbox_ref;
        settings_sync <= settings_meta;
    end
    always @(negedge fixture.clk) begin
        fixture.image_request = request_sync[2] ^ request_sync[1];
        fixture.image_request_idx = index_sync;
        fixture.image_request_zoom = zoom_sync;
        fixture.image_request_prev = prev_sync;
        fixture.image_request_settings = settings_sync;
        if (fixture.image_request) begin
            requests = requests+1;
            $display("REQUEST slot=%0d", index_sync);
        end
        if (complete_frames && fixture.dut.source_done_seen &&
            completed_load != fixture.load_count) begin
            fixture.write_finish_toggle = ~fixture.write_finish_toggle;
            completed_load = fixture.load_count;
        end
        if (fixture.display_commit_toggle != commit_seen) begin
            commit_seen = fixture.display_commit_toggle;
            commits = commits+1;
            $display("COMMIT slot=%0d", fixture.display_image_idx);
        end
        if (complete_frames)
            fixture.display_commit_ack_toggle = fixture.display_commit_toggle;
    end

    task automatic settle;
        repeat (100) @(negedge clk);
    endtask
    task automatic click;
        @(negedge clk); learn_key_short[0]=1;
        @(negedge clk); learn_key_short[0]=0;
    endtask
    task automatic single_next(input [2:0] target);
        click(); settle();
        if (page_index != target || fixture.display_image_idx != target ||
            fixture.display_zoom_level !=
                ((target == 0) ? 3'd4 : (target == 1) ? 3'd1 : 3'd3))
            $fatal(1,"single next failed target=%0d",target);
    endtask
    task automatic double_prev(input [2:0] target, input integer moves,
                               input integer gap);
        before_req=requests; before_load=fixture.load_count; before_commit=commits;
        click(); repeat (gap) @(negedge clk);
        if (requests != before_req || fixture.load_count != before_load ||
            commits != before_commit)
            $fatal(1,"FIRST_CLICK_ESCAPED: previous went through another image");
        click(); settle();
        if (page_index != target || requests-before_req != moves ||
            fixture.load_count-before_load != moves || commits-before_commit != moves ||
            fixture.display_image_idx != target ||
            fixture.display_zoom_level !=
                ((target == 0) ? 3'd4 : (target == 1) ? 3'd1 : 3'd3))
            $fatal(1,"double previous target=%0d req/load/commit=%0d/%0d/%0d",target,
                requests-before_req,fixture.load_count-before_load,commits-before_commit);
    endtask
    task automatic go_home;
        @(negedge clk); learn_key_long[1]=1;
        @(negedge clk); learn_key_long[1]=0;
        settle();
        if (learn_state != APP_ST_HOME) $fatal(1,"KEY4 long failed HOME");
    endtask
    task automatic enter_learn;
        @(negedge clk); select_event=1;
        @(negedge clk); select_event=0;
        settle();
        if (learn_state != APP_ST_LEARN || page_index != 0)
            $fatal(1,"failed to enter learning");
    endtask

    initial begin
        repeat (4) @(negedge fixture.clk);
        fixture.rst=0;
        fixture.dut.sd_card_top_m0.sd_init_done=1;
        fixture.dut.bmp_read_m0.ready=1;
        wait (fixture.dut.scan_start_pulse);
        fixture.dut.u_fat32_volume_scanner.state=0;
        fixture.dut.bmp_read_m0.ready=0;
        for (index=0; index<12; index=index+1) fixture.report_found(index);
        fixture.finish_scan();
        fixture.dut.bmp_read_m0.ready=1;
        settle();
        @(negedge clk); rst_ref=0; boot_done=1;
        @(negedge clk); boot_done=0;
        enter_learn();
        single_next(1); single_next(2);
        // Reproduce exactly: page 3 -> double click -> page 2, without page 1.
        double_prev(1,1,3); double_prev(0,1,3); double_prev(0,0,3);
        // Slower 350 ms and near-limit 475 ms release intervals must each
        // request/load/commit only the previous page, never wrap through 1.
        single_next(1); single_next(2);
        double_prev(1,1,12);
        single_next(2);
        double_prev(1,1,17);
        // Once outside the 500 ms window, these are two distinct singles.
        single_next(2);
        before_req=requests; before_load=fixture.load_count; before_commit=commits;
        click(); repeat (25) @(negedge clk); click(); settle();
        if (page_index != 1 || fixture.display_image_idx != 1 ||
            requests-before_req != 2 || fixture.load_count-before_load != 2 ||
            commits-before_commit != 2)
            $fatal(1,"outside-window singles were lost or treated as previous");
        double_prev(0,1,3);
        single_next(1); single_next(2); single_next(0);

        // Modifier adjustments stay immediate and cannot navigate.
        lesson_volume_adjust_active=1;
        @(negedge clk); learn_key_short[0]=1; #1;
        if (!key2_single_event || nav_next_event || nav_prev_event)
            $fatal(1,"volume click deferred or navigated");
        @(negedge clk); learn_key_short=0;
        settle(); lesson_volume_adjust_active=0;
        lesson_speed_adjust_active=1;
        @(negedge clk); learn_key_short[0]=1; #1;
        if (!key2_single_event || nav_next_event || nav_prev_event)
            $fatal(1,"speed click deferred or navigated");
        @(negedge clk); learn_key_short=0;
        settle(); lesson_speed_adjust_active=0;
        if (page_index != 0) $fatal(1,"modifier changed page");

        // Entering adjustment mode cancels a pending navigation click.
        click(); lesson_volume_adjust_active=1;
        settle(); lesson_volume_adjust_active=0;
        if (page_index != 0) $fatal(1,"pending click leaked from adjustment");

        // Long KEY2 cancels a pending single and performs one previous move.
        single_next(1); single_next(2);
        before_req=requests;
        click();
        @(negedge clk); learn_key_long[0]=1;
        @(negedge clk); learn_key_long=0;
        settle();
        if (page_index != 1 || requests-before_req != 1)
            $fatal(1,"long previous leaked a single");

        // Navigation while the writer is busy queues only intended targets.
        single_next(2);
        complete_frames=0;
        click(); repeat (3) @(negedge clk); click(); settle();
        if (page_index != 1 || fixture.display_image_idx != 2)
            $fatal(1,"incomplete frame became visible");
        click(); repeat (3) @(negedge clk); click(); settle();
        if (page_index != 0 || fixture.display_image_idx != 2)
            $fatal(1,"queued previous exposed incomplete image");
        before_commit=commits; before_load=fixture.load_count;
        complete_frames=1; settle();
        if (fixture.display_image_idx != 0 || commits-before_commit != 2 ||
            fixture.load_count-before_load != 1)
            $fatal(1,"busy navigation lost or added a commit");

        // Existing automatic-next input remains independent of click deferral.
        @(negedge clk); lesson_auto_next_event=1;
        @(negedge clk); lesson_auto_next_event=0;
        settle();
        if (page_index != 1 || fixture.display_image_idx != 1)
            $fatal(1,"auto advance failed");
        click(); go_home();
        enter_learn();
        if (page_index != 0) $fatal(1,"HOME leaked pending click");
        click();
        @(negedge clk); rst_ref=1;
        repeat (3) @(negedge clk);
        rst_ref=0; boot_done=1;
        @(negedge clk); boot_done=0;
        enter_learn();
        if (page_index != 0) $fatal(1,"reset leaked pending click");
        single_next(1);
        go_home();
        repeat (2) begin click(); settle(); end
        @(negedge clk); select_event=1;
        @(negedge clk); select_event=0;
        settle();
        if (learn_state != APP_ST_SETTINGS || fixture.display_image_idx != 0 ||
            !fixture.display_settings_entry)
            $fatal(1,"SETTINGS did not request lesson zero with fade tag");
        $display("TEST_PASS tb_learning_navigation: real top routes, slow 350ms/475ms 3->2, outside window, boundary, single, modifiers, long, busy commits, HOME, reset, auto");
        $finish;
    end
    initial begin
        #2000000; $fatal(1,"navigation timeout");
    end
endmodule
