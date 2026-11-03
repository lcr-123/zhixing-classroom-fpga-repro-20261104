`timescale 1ns/1ps

// Compact eight-digit, active-low seven-segment status formatter.
//
// digit7 is the left-most character and digit0 is the right-most character.
// Long words are deliberately avoided: the left-most digit identifies the
// application context and the right-most digit carries the page, option or
// setting index that changes inside that context.
module learning_seg_status (
    input  wire [3:0]  app_state,
    input  wire [2:0]  question_index,
    input  wire [3:0]  boot_state_code,
    input  wire [1:0]  settings_index,
    input  wire        answer_selection_valid,
    input  wire [1:0]  answer_choice,
    input  wire        answer_correct,
    input  wire        sound_quiz_active,
    input  wire        sound_quiz_feedback,
    input  wire        sound_quiz_complete,
    input  wire        sound_quiz_answer_correct,
    output reg  [63:0] segments
);

localparam [3:0] ST_BOOT_SELFTEST = 4'd0;
localparam [3:0] ST_HOME          = 4'd1;
localparam [3:0] ST_LEARN         = 4'd2;
localparam [3:0] ST_QUIZ          = 4'd3;
localparam [3:0] ST_FEEDBACK      = 4'd4;
localparam [3:0] ST_WRONG_REVIEW  = 4'd5;
localparam [3:0] ST_SOUND_LAB     = 4'd6;
localparam [3:0] ST_SETTINGS      = 4'd7;
localparam [3:0] ST_SUMMARY       = 4'd8;

// {decimal-point, gfedcba}; all outputs are active-low.
localparam [7:0] SEG_BLANK = 8'b1_1111111;
localparam [7:0] SEG_DASH  = 8'b1_0111111;
localparam [7:0] SEG_1     = 8'b1_1111001;
localparam [7:0] SEG_2     = 8'b1_0100100;
localparam [7:0] SEG_3     = 8'b1_0110000;
localparam [7:0] SEG_4     = 8'b1_0011001;
localparam [7:0] SEG_A     = 8'b1_0001000;
localparam [7:0] SEG_B     = 8'b1_0000011;
localparam [7:0] SEG_C     = 8'b1_1000110;
localparam [7:0] SEG_D     = 8'b1_0100001;
localparam [7:0] SEG_E     = 8'b1_0000110;
localparam [7:0] SEG_H     = 8'b1_0001001;
localparam [7:0] SEG_L     = 8'b1_1000111;
localparam [7:0] SEG_O     = 8'b1_1000000;
localparam [7:0] SEG_R     = 8'b1_0101111;
localparam [7:0] SEG_S     = 8'b1_0010010;

localparam [63:0] DISPLAY_LOADING =
    {SEG_BLANK, SEG_BLANK, SEG_DASH, SEG_DASH,
     SEG_DASH, SEG_BLANK, SEG_BLANK, SEG_BLANK};
localparam [63:0] DISPLAY_HELLO =
    {SEG_BLANK, SEG_H, SEG_E, SEG_L,
     SEG_L, SEG_O, SEG_BLANK, SEG_BLANK};
localparam [63:0] DISPLAY_ERROR =
    {SEG_BLANK, SEG_BLANK, SEG_BLANK, SEG_E,
     SEG_BLANK, SEG_BLANK, SEG_BLANK, SEG_BLANK};
localparam [63:0] DISPLAY_RESULT =
    {SEG_R, SEG_BLANK, SEG_BLANK, SEG_BLANK,
     SEG_BLANK, SEG_BLANK, SEG_BLANK, SEG_BLANK};
localparam [63:0] DISPLAY_AUDIO =
    {SEG_A, SEG_BLANK, SEG_BLANK, SEG_BLANK,
     SEG_BLANK, SEG_BLANK, SEG_BLANK, SEG_BLANK};

reg [7:0] page_segment;
reg [7:0] setting_segment;
reg [7:0] answer_segment;
reg [7:0] feedback_segment;

always @* begin
    case (question_index)
        3'd0: page_segment = SEG_1;
        3'd1: page_segment = SEG_2;
        3'd2: page_segment = SEG_3;
        default: page_segment = SEG_E;
    endcase

    case (settings_index)
        2'd0: setting_segment = SEG_1;
        2'd1: setting_segment = SEG_2;
        2'd2: setting_segment = SEG_3;
        2'd3: setting_segment = SEG_4;
        default: setting_segment = SEG_E;
    endcase

    if (!answer_selection_valid) begin
        answer_segment = SEG_E;
    end else begin
        case (answer_choice)
            2'd0: answer_segment = SEG_A;
            2'd1: answer_segment = SEG_B;
            2'd2: answer_segment = SEG_C;
            default: answer_segment = SEG_D;
        endcase
    end

    feedback_segment = answer_correct ? SEG_C : SEG_E;

    segments = DISPLAY_ERROR;
    case (app_state)
        ST_BOOT_SELFTEST: begin
            if ((boot_state_code == 4'he) || (boot_state_code == 4'hf))
                segments = DISPLAY_ERROR;
            else
                segments = DISPLAY_LOADING;
        end

        ST_HOME:
            segments = DISPLAY_HELLO;

        ST_LEARN:
            segments = {SEG_L, SEG_BLANK, SEG_BLANK, SEG_BLANK,
                        SEG_BLANK, SEG_BLANK, SEG_BLANK, page_segment};

        ST_QUIZ:
            segments = {SEG_E, SEG_BLANK, SEG_BLANK, SEG_BLANK,
                        SEG_BLANK, SEG_BLANK, SEG_BLANK, answer_segment};

        ST_FEEDBACK:
            segments = {SEG_E, SEG_BLANK, SEG_BLANK, SEG_BLANK,
                        SEG_BLANK, SEG_BLANK, SEG_BLANK, feedback_segment};

        ST_WRONG_REVIEW:
            segments = {SEG_E, SEG_BLANK, SEG_BLANK, SEG_BLANK,
                        SEG_BLANK, SEG_BLANK, SEG_BLANK, answer_segment};

        ST_SOUND_LAB: begin
            if (!sound_quiz_active)
                segments = DISPLAY_AUDIO;
            else if (sound_quiz_complete)
                segments = DISPLAY_RESULT;
            else if (sound_quiz_feedback)
                segments = {SEG_E, SEG_BLANK, SEG_BLANK, SEG_BLANK,
                            SEG_BLANK, SEG_BLANK, SEG_BLANK,
                            sound_quiz_answer_correct ? SEG_C : SEG_E};
            else
                segments = {SEG_E, SEG_BLANK, SEG_BLANK, SEG_BLANK,
                            SEG_BLANK, SEG_BLANK, SEG_BLANK, answer_segment};
        end

        ST_SETTINGS:
            segments = {SEG_S, SEG_BLANK, SEG_BLANK, SEG_BLANK,
                        SEG_BLANK, SEG_BLANK, SEG_BLANK, setting_segment};

        ST_SUMMARY:
            segments = DISPLAY_RESULT;

        default:
            segments = DISPLAY_ERROR;
    endcase
end

endmodule
