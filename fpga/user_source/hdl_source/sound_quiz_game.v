`timescale 1ns/1ps

// Three-question listening game in the 50 MHz application clock domain.
//
// Question 0 asks for pitch, question 1 for amplitude, and question 2 for
// waveform. Answers arrive from the shared course selector, so the physical
// convention is SW1=A, SW2=B, SW3=C or KEY2 cycle with all switches down.
// Codes are 0=low/square, 1=middle/triangle, 2=high/sine. Invalid/ambiguous
// selections and code 3 are rejected without advancing or changing score.
//
// Scoring is deliberately delegated to quiz_engine so the English quiz and
// sound game share the same acceptance, locking, percentage, and star rules.
module sound_quiz_game (
    input  wire       clk,
    input  wire       rst,
    input  wire       lab_active,
    input  wire       toggle_game_pulse,
    input  wire       advance_pulse,
    input  wire       submit_pulse,
    input  wire [1:0] answer_code,
    input  wire       answer_valid,

    output wire       game_active,
    output wire       feedback_active,
    output wire       game_complete,
    output reg  [1:0] question_index,
    output wire [1:0] selected_answer,
    output reg  [1:0] expected_answer,
    output wire       answer_correct,
    output wire [3:0] answered_count,
    output wire [3:0] correct_count,
    output wire [7:0] score_percent,
    output wire [1:0] star_level,

    output reg  [1:0] audio_frequency,
    output reg  [1:0] audio_amplitude,
    output reg  [1:0] audio_waveform,
    output reg        audio_muted
);

localparam [1:0] GAME_IDLE     = 2'd0;
localparam [1:0] GAME_QUESTION = 2'd1;
localparam [1:0] GAME_FEEDBACK = 2'd2;
localparam [1:0] GAME_COMPLETE = 2'd3;

reg [1:0] game_state;
reg [7:0] random_lfsr;
reg       session_clear_pulse;
reg       score_submit_pulse;
reg       score_feedback_done;

wire score_quiz_complete;

function [1:0] normalized_random;
    input [1:0] random_bits;
    begin
        normalized_random = (random_bits == 2'b11) ? 2'd0 : random_bits;
    end
endfunction

assign game_active     = (game_state != GAME_IDLE);
assign feedback_active = (game_state == GAME_FEEDBACK);
assign game_complete   = (game_state == GAME_COMPLETE);
assign selected_answer = answer_code;

always @(posedge clk) begin
    if (rst) begin
        random_lfsr  <= 8'hA5;
    end else begin
        // Free-running non-zero LFSR makes a new round depend on when the
        // learner enters it, while remaining fully deterministic in RTL sim.
        random_lfsr <= {random_lfsr[6:0],
                        random_lfsr[7] ^ random_lfsr[5] ^
                        random_lfsr[4] ^ random_lfsr[3]};
    end
end

always @(posedge clk) begin
    if (rst) begin
        game_state          <= GAME_IDLE;
        question_index      <= 2'd0;
        expected_answer     <= 2'd0;
        session_clear_pulse <= 1'b0;
        score_submit_pulse  <= 1'b0;
        score_feedback_done <= 1'b0;
    end else begin
        session_clear_pulse <= 1'b0;
        score_submit_pulse  <= 1'b0;
        score_feedback_done <= 1'b0;

        if (!lab_active) begin
            game_state     <= GAME_IDLE;
            question_index <= 2'd0;
        end else if (toggle_game_pulse) begin
            if (game_state == GAME_IDLE) begin
                game_state          <= GAME_QUESTION;
                question_index      <= 2'd0;
                expected_answer     <= normalized_random(random_lfsr[1:0]);
                session_clear_pulse <= 1'b1;
            end else begin
                game_state <= GAME_IDLE;
            end
        end else begin
            case (game_state)
                GAME_QUESTION: begin
                    if (submit_pulse && answer_valid &&
                        (answer_code != 2'b11)) begin
                        score_submit_pulse <= 1'b1;
                        game_state         <= GAME_FEEDBACK;
                    end
                end

                GAME_FEEDBACK: begin
                    if (advance_pulse) begin
                        score_feedback_done <= 1'b1;
                        if (score_quiz_complete) begin
                            game_state <= GAME_COMPLETE;
                        end else begin
                            question_index  <= question_index + 2'd1;
                            expected_answer <= normalized_random(random_lfsr[3:2]);
                            game_state      <= GAME_QUESTION;
                        end
                    end
                end

                GAME_COMPLETE: begin
                    // A short KEY2 press starts a clean three-question round.
                    if (advance_pulse) begin
                        game_state          <= GAME_QUESTION;
                        question_index      <= 2'd0;
                        expected_answer     <= normalized_random(random_lfsr[5:4]);
                        session_clear_pulse <= 1'b1;
                    end
                end

                default: begin
                    game_state     <= GAME_IDLE;
                    question_index <= 2'd0;
                end
            endcase
        end
    end
end

quiz_engine #(
    .QUESTION_COUNT(3)
) u_sound_quiz_score (
    .clk                (clk),
    .rst                (rst),
    .session_clear      (session_clear_pulse),
    .submit_valid       (score_submit_pulse),
    .feedback_done      (score_feedback_done),
    .review_mode        (1'b0),
    .question_index     ({1'b0, question_index}),
    .selected_answer    (answer_code),
    .expected_answer    (expected_answer),
    .question_count     (3'd3),
    .submit_accepted    (),
    .answer_correct     (answer_correct),
    .answer_locked      (),
    .mark_wrong_pulse   (),
    .mark_correct_pulse (),
    .quiz_complete      (score_quiz_complete),
    .answered_count     (answered_count),
    .correct_count      (correct_count),
    .current_streak     (),
    .max_streak         (),
    .score_percent      (score_percent),
    .star_level         (star_level),
    .answered_bitmap    ()
);

// Keep non-tested dimensions at a fixed middle/sine reference so each round
// isolates exactly one audible property.  The completed game is muted until
// the learner restarts or exits to the free sound laboratory.
always @* begin
    audio_frequency = 2'd1;
    audio_amplitude = 2'd1;
    audio_waveform  = 2'd2;
    audio_muted     = game_complete;

    case (question_index)
        2'd0: audio_frequency = expected_answer;
        2'd1: audio_amplitude = expected_answer;
        2'd2: audio_waveform  = expected_answer;
        default: begin
            audio_frequency = 2'd1;
            audio_amplitude = 2'd1;
            audio_waveform  = 2'd2;
        end
    endcase
end

endmodule
