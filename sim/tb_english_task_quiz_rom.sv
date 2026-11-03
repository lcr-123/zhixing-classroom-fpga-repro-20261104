`timescale 1ns/1ps

module tb_english_task_quiz_rom;
    reg [1:0] card_index = 2'd0;
    reg [1:0] question_id = 2'd0;
    wire question_valid;
    wire [2:0] question_type;
    wire [7:0] prompt_token;
    wire [7:0] option_a_token;
    wire [7:0] option_b_token;
    wire [7:0] option_c_token;
    wire [7:0] option_d_token;
    wire [1:0] correct_answer;
    wire [1:0] difficulty;

    english_task_quiz_rom dut (
        .card_index(card_index),
        .question_id(question_id),
        .question_valid(question_valid),
        .question_type(question_type),
        .prompt_token(prompt_token),
        .option_a_token(option_a_token),
        .option_b_token(option_b_token),
        .option_c_token(option_c_token),
        .option_d_token(option_d_token),
        .correct_answer(correct_answer),
        .difficulty(difficulty)
    );

    task automatic check_question(
        input [1:0] card,
        input [2:0] kind,
        input [7:0] prompt,
        input [1:0] answer,
        input [1:0] level
    );
        begin
            card_index = card;
            question_id = card;
            #1;
            if (!question_valid || question_type != kind ||
                prompt_token != prompt || correct_answer != answer ||
                difficulty != level)
                $fatal(1, "question metadata mismatch for card %0d", card);
            if ((option_a_token == 8'h00) || (option_b_token == 8'h00) ||
                (option_c_token == 8'h00) || (option_d_token == 8'h00))
                $fatal(2, "missing answer option for card %0d", card);
        end
    endtask

    initial begin
        check_question(2'd0, 3'd6, 8'h50, 2'd3, 2'd1);
        check_question(2'd1, 3'd1, 8'h60, 2'd1, 2'd1);
        check_question(2'd2, 3'd0, 8'h70, 2'd1, 2'd2);
        check_question(2'd3, 3'd7, 8'h80, 2'd0, 2'd2);

        // A mismatched card/question pair must not leak another question.
        card_index = 2'd1;
        question_id = 2'd2;
        #1;
        if (question_valid || prompt_token != 8'h00 || correct_answer != 2'd0)
            $fatal(3, "mismatched question pair was accepted");

        $display("TEST_PASS tb_english_task_quiz_rom");
        $finish;
    end
endmodule
