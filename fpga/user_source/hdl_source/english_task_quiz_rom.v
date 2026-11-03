`timescale 1ns/1ps

// Interdisciplinary Grade 4A question metadata for the four textbook-aligned
// exercise cards.  The legacy module name is retained to avoid changing the
// stable TD source list; its contents now cover Chinese, maths, English, and
// music in that order.
// Text is kept out of RTL; prompt/option tokens are stable IDs for a future
// OSD, host UI, or small text/icon ROM. The answer encoding is A=0, B=1,
// C=2, D=3 and matches quiz_engine.selected_answer.
//
// Card 0 Chinese: which verse describes the crescent like a bow? -> D
// Card 1 Maths: read the marked angle -> 60 degrees (B)
// Card 2 English: The students sit at their ____ -> desks (B)
// Card 3 Music: identify the pitch-and-waveform combination used for a
// Xiao Luo Hao excerpt -> high + square wave (A).
module english_task_quiz_rom (
    input  wire [1:0] card_index,
    input  wire [1:0] question_id,
    output reg        question_valid,
    output reg  [2:0] question_type,
    output reg  [7:0] prompt_token,
    output reg  [7:0] option_a_token,
    output reg  [7:0] option_b_token,
    output reg  [7:0] option_c_token,
    output reg  [7:0] option_d_token,
    output reg  [1:0] correct_answer,
    output reg  [1:0] difficulty
);

    localparam [2:0] TYPE_WORD         = 3'd0;
    localparam [2:0] TYPE_COUNT        = 3'd1;
    localparam [2:0] TYPE_COLOR        = 3'd2;
    localparam [2:0] TYPE_PREPOSITION  = 3'd3;
    localparam [2:0] TYPE_ACTION       = 3'd4;
    localparam [2:0] TYPE_FOOD_REQUEST = 3'd5;
    localparam [2:0] TYPE_LITERATURE    = 3'd6;
    localparam [2:0] TYPE_SOUND         = 3'd7;

    always @* begin
        question_valid = 1'b0;
        question_type = TYPE_WORD;
        prompt_token = 8'h00;
        option_a_token = 8'h00;
        option_b_token = 8'h00;
        option_c_token = 8'h00;
        option_d_token = 8'h00;
        correct_answer = 2'd0;
        difficulty = 2'd0;

        if (card_index == question_id) begin
            question_valid = 1'b1;
            case (card_index)
                2'd0: begin
                    question_type = TYPE_LITERATURE;
                    prompt_token = 8'h50; // CRESCENT_LIKE_BOW_VERSE
                    option_a_token = 8'h51;
                    option_b_token = 8'h52;
                    option_c_token = 8'h53;
                    option_d_token = 8'h54; // CORRECT_VERSE
                    correct_answer = 2'd3;
                    difficulty = 2'd1;
                end
                2'd1: begin
                    question_type = TYPE_COUNT;
                    prompt_token = 8'h60; // PROTRACTOR_ANGLE_READING
                    option_a_token = 8'h61; // 30_DEGREES
                    option_b_token = 8'h62; // 60_DEGREES
                    option_c_token = 8'h63; // 120_DEGREES
                    option_d_token = 8'h64; // 150_DEGREES
                    correct_answer = 2'd1;
                    difficulty = 2'd1;
                end
                2'd2: begin
                    question_type = TYPE_WORD;
                    prompt_token = 8'h70; // STUDENTS_SIT_AT_THEIR_BLANK
                    option_a_token = 8'h71; // WINDOWS
                    option_b_token = 8'h72; // DESKS
                    option_c_token = 8'h73; // DOORS
                    option_d_token = 8'h74; // LIGHTS
                    correct_answer = 2'd1;
                    difficulty = 2'd2;
                end
                2'd3: begin
                    question_type = TYPE_SOUND;
                    prompt_token = 8'h80; // PITCH_AND_WAVEFORM
                    option_a_token = 8'h81; // HIGH_SQUARE
                    option_b_token = 8'h82; // MIDDLE_TRIANGLE
                    option_c_token = 8'h83; // LOW_SINE
                    option_d_token = 8'h84; // MIDDLE_SINE
                    correct_answer = 2'd0;
                    difficulty = 2'd2;
                end
                default: begin
                    question_valid = 1'b0;
                end
            endcase
        end
    end

endmodule
