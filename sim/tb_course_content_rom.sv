`timescale 1ns/1ps

module tb_course_content_rom;
    reg [2:0] course_index = 3'd0;
    reg [2:0] available_count = 3'd0;
    wire course_valid;
    wire safe_home_request;
    wire [2:0] image_index;
    wire [2:0] page_number;
    wire [1:0] question_id;
    wire [1:0] correct_answer;
    wire [2:0] next_course_index;
    wire auto_play_allowed;
    wire [10:0] expected_width;
    wire [9:0] expected_height;

    course_content_rom dut (
        .course_index(course_index),
        .available_count(available_count),
        .course_valid(course_valid),
        .safe_home_request(safe_home_request),
        .image_index(image_index),
        .page_number(page_number),
        .question_id(question_id),
        .correct_answer(correct_answer),
        .next_course_index(next_course_index),
        .auto_play_allowed(auto_play_allowed),
        .expected_width(expected_width),
        .expected_height(expected_height)
    );

    task automatic check_valid_card(
        input [2:0] index,
        input [2:0] expected_next,
        input [1:0] expected_answer,
        input [10:0] width,
        input [9:0] height
    );
        begin
            course_index = index;
            #1;
            if (!course_valid || safe_home_request)
                $fatal(1, "valid card %0d was rejected", index);
            if (image_index != index ||
                page_number != index + 3'd1 ||
                question_id != index[1:0] ||
                correct_answer != expected_answer)
                $fatal(2, "metadata mismatch for card %0d", index);
            if (next_course_index != expected_next)
                $fatal(3, "next card mismatch for card %0d", index);
            if (!auto_play_allowed)
                $fatal(4, "auto play unexpectedly disabled for card %0d", index);
            if (expected_width != width || expected_height != height)
                $fatal(5, "source dimensions mismatch for card %0d", index);
        end
    endtask

    task automatic check_safe_invalid(input [2:0] index);
        begin
            course_index = index;
            #1;
            if (course_valid || !safe_home_request)
                $fatal(6, "invalid card %0d did not request HOME", index);
            if (image_index != 3'd0 || page_number != 3'd0 ||
                question_id != 2'd0 || correct_answer != 2'd0 ||
                next_course_index != 3'd0 || auto_play_allowed ||
                expected_width != 11'd0 || expected_height != 10'd0)
                $fatal(7, "invalid card %0d leaked metadata", index);
        end
    endtask

    initial begin
        available_count = 3'd4;
        check_valid_card(3'd0, 3'd1, 2'd3, 11'd640, 10'd480);
        check_valid_card(3'd1, 3'd2, 2'd1, 11'd640, 10'd480);
        check_valid_card(3'd2, 3'd3, 2'd1, 11'd640, 10'd480);
        check_valid_card(3'd3, 3'd0, 2'd0, 11'd640, 10'd480);
        check_safe_invalid(3'd4);
        check_safe_invalid(3'd7);

        // With only two discovered BMPs, navigation must wrap inside the
        // discovered subset and must not expose card 2 or 3.
        available_count = 3'd2;
        check_valid_card(3'd0, 3'd1, 2'd3, 11'd640, 10'd480);
        check_valid_card(3'd1, 3'd0, 2'd1, 11'd640, 10'd480);
        check_safe_invalid(3'd2);

        // One card is valid but automatic playback is intentionally disabled.
        available_count = 3'd1;
        course_index = 3'd0;
        #1;
        if (!course_valid || auto_play_allowed || next_course_index != 3'd0)
            $fatal(8, "single-card policy failed");

        // Empty scan results always request the safe HOME path.
        available_count = 3'd0;
        check_safe_invalid(3'd0);

        // Corrupt counts above the physical four-card capacity are clamped;
        // they cannot make an illegal image index visible.
        available_count = 3'd7;
        check_valid_card(3'd3, 3'd0, 2'd0, 11'd640, 10'd480);
        check_safe_invalid(3'd4);

        $display("TEST_PASS tb_course_content_rom");
        $finish;
    end
endmodule
