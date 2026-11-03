`timescale 1ns/1ps

module tb_english_nature_metadata;
reg clk = 1'b0;
reg rst = 1'b1;
reg session_start = 1'b0;
reg [15:0] entropy_counter = 16'h1234;
reg [1:0] vocabulary_count = 2'd3;
reg [1:0] sentence_count = 2'd3;
reg [1:0] question_count = 2'd3;
reg [3:0] image_index = 4'd0;
reg [3:0] available_count = 4'd12;
wire card_valid, safe_home_request, learning_page, question_page;
wire [1:0] metadata_group, group_index, metadata_answer;
wire [10:0] expected_width;
wire [9:0] expected_height;
wire question_valid;
wire [1:0] rom_group, rom_answer, difficulty;
wire [7:0] prompt_token, option_a_token, option_b_token, option_c_token, option_d_token;
wire selection_valid, selection_fault;
wire [3:0] question_image0, question_image1, question_image2;
integer i;
reg [1:0] expected_answers [3:11];

always #5 clk = ~clk;

english_nature_course_rom u_course (
    .image_index(image_index), .available_count(available_count),
    .card_valid(card_valid), .safe_home_request(safe_home_request),
    .learning_page(learning_page), .question_page(question_page),
    .question_group(metadata_group), .group_index(group_index),
    .correct_answer(metadata_answer), .expected_width(expected_width),
    .expected_height(expected_height)
);

english_nature_question_rom u_question (
    .image_index(image_index), .question_valid(question_valid),
    .question_group(rom_group), .prompt_token(prompt_token),
    .option_a_token(option_a_token), .option_b_token(option_b_token),
    .option_c_token(option_c_token), .option_d_token(option_d_token),
    .correct_answer(rom_answer), .difficulty(difficulty)
);

random_three_question_selector u_selector (
    .clk(clk), .rst(rst), .session_start(session_start),
    .entropy_counter(entropy_counter), .vocabulary_count(vocabulary_count),
    .sentence_count(sentence_count), .question_count(question_count),
    .selection_valid(selection_valid), .selection_fault(selection_fault),
    .question_image0(question_image0), .question_image1(question_image1),
    .question_image2(question_image2)
);

task start_session;
    input [15:0] entropy;
    begin
        entropy_counter = entropy;
        @(negedge clk); session_start = 1'b1;
        @(negedge clk); session_start = 1'b0;
        #1;
    end
endtask

initial begin
    expected_answers[3]=2'd2; expected_answers[4]=2'd1; expected_answers[5]=2'd3;
    expected_answers[6]=2'd1; expected_answers[7]=2'd0; expected_answers[8]=2'd2;
    expected_answers[9]=2'd0; expected_answers[10]=2'd2; expected_answers[11]=2'd3;
    repeat (2) @(negedge clk); rst = 1'b0;

    for (i = 0; i < 12; i = i + 1) begin
        image_index = i[3:0]; #1;
        if (!card_valid || safe_home_request ||
            expected_width != (i < 3 ? 640 : i < 6 ? 1280 : i < 9 ? 800 : 320) ||
            expected_height != (i < 3 ? 480 : i < 6 ? 960 : i < 9 ? 600 : 240))
            $fatal(1, "card metadata invalid at image %0d", i);
        if (i < 3) begin
            if (!learning_page || question_page || question_valid)
                $fatal(2, "learning card classification invalid at image %0d", i);
        end else begin
            if (learning_page || !question_page || !question_valid ||
                metadata_answer != expected_answers[i] || rom_answer != expected_answers[i])
                $fatal(3, "question metadata invalid at image %0d", i);
        end
    end

    image_index = 4'd12; #1;
    if (card_valid || !safe_home_request || question_valid)
        $fatal(4, "out-of-range image did not fail safely");
    available_count = 4'd2; image_index = 4'd0; #1;
    if (card_valid || !safe_home_request)
        $fatal(5, "short learning set did not request safe recovery");
    available_count = 4'd12;

    start_session(16'h1234);
    if (!selection_valid || selection_fault || question_image0 < 4'd3 || question_image0 > 4'd5 ||
        question_image1 < 4'd6 || question_image1 > 4'd8 ||
        question_image2 < 4'd9 || question_image2 > 4'd11)
        $fatal(6, "three-pool selection is out of range");
    image_index = question_image0; #1;
    if (!question_valid || rom_group != 2'd0) $fatal(7, "vocabulary selection metadata mismatch");
    image_index = question_image1; #1;
    if (!question_valid || rom_group != 2'd1) $fatal(8, "sentence selection metadata mismatch");
    image_index = question_image2; #1;
    if (!question_valid || rom_group != 2'd2) $fatal(9, "question selection metadata mismatch");

    vocabulary_count = 2'd0;
    start_session(16'hBEEF);
    if (selection_valid || !selection_fault || question_image0 != 4'd3)
        $fatal(10, "empty-pool fallback is not bounded");

    rst = 1'b1; @(negedge clk); rst = 1'b0; #1;
    if (selection_valid || selection_fault || question_image0 != 4'd3 ||
        question_image1 != 4'd6 || question_image2 != 4'd9)
        $fatal(11, "reset defaults are invalid");

    $display("TEST_PASS tb_english_nature_metadata");
    $finish;
end
endmodule
