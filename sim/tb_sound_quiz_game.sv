`timescale 1ns/1ps

module tb_sound_quiz_game;

reg clk;
reg rst;
reg lab_active;
reg toggle_game_pulse;
reg advance_pulse;
reg submit_pulse;
reg [1:0] answer_code;
reg answer_valid;

wire game_active;
wire feedback_active;
wire game_complete;
wire [1:0] question_index;
wire [1:0] selected_answer;
wire [1:0] expected_answer;
wire answer_correct;
wire [3:0] answered_count;
wire [3:0] correct_count;
wire [7:0] score_percent;
wire [1:0] star_level;
wire [1:0] audio_frequency;
wire [1:0] audio_amplitude;
wire [1:0] audio_waveform;
wire audio_muted;

sound_quiz_game dut (
    .clk(clk),
    .rst(rst),
    .lab_active(lab_active),
    .toggle_game_pulse(toggle_game_pulse),
    .advance_pulse(advance_pulse),
    .submit_pulse(submit_pulse),
    .answer_code(answer_code),
    .answer_valid(answer_valid),
    .game_active(game_active),
    .feedback_active(feedback_active),
    .game_complete(game_complete),
    .question_index(question_index),
    .selected_answer(selected_answer),
    .expected_answer(expected_answer),
    .answer_correct(answer_correct),
    .answered_count(answered_count),
    .correct_count(correct_count),
    .score_percent(score_percent),
    .star_level(star_level),
    .audio_frequency(audio_frequency),
    .audio_amplitude(audio_amplitude),
    .audio_waveform(audio_waveform),
    .audio_muted(audio_muted)
);

always #5 clk = ~clk;

task pulse_toggle;
begin
    @(negedge clk);
    toggle_game_pulse = 1'b1;
    @(negedge clk);
    toggle_game_pulse = 1'b0;
    repeat (3) @(negedge clk);
end
endtask

task pulse_submit;
begin
    @(negedge clk);
    submit_pulse = 1'b1;
    @(negedge clk);
    submit_pulse = 1'b0;
    repeat (3) @(negedge clk);
end
endtask

task pulse_advance;
begin
    @(negedge clk);
    advance_pulse = 1'b1;
    @(negedge clk);
    advance_pulse = 1'b0;
    repeat (3) @(negedge clk);
end
endtask

task choose_answer;
    input [1:0] value;
begin
    answer_code = value;
    answer_valid = (value != 2'b11);
    @(negedge clk);
end
endtask

function [1:0] wrong_choice;
    input [1:0] expected;
    begin
        wrong_choice = (expected == 2'd2) ? 2'd0 : expected + 2'd1;
    end
endfunction

initial begin
    clk = 1'b0;
    rst = 1'b1;
    lab_active = 1'b0;
    toggle_game_pulse = 1'b0;
    advance_pulse = 1'b0;
    submit_pulse = 1'b0;
    answer_code = 2'd0;
    answer_valid = 1'b1;

    repeat (3) @(negedge clk);
    rst = 1'b0;
    lab_active = 1'b1;
    repeat (2) @(negedge clk);
    pulse_toggle();

    if (!game_active || feedback_active || game_complete ||
        (question_index != 2'd0))
        $fatal(1, "game did not start on pitch question");
    if ((audio_frequency != expected_answer) ||
        (audio_amplitude != 2'd1) || (audio_waveform != 2'd2) ||
        audio_muted)
        $fatal(2, "pitch question did not isolate frequency");

    answer_code = 2'd0;
    answer_valid = 1'b0;
    pulse_submit();
    if (feedback_active || (answered_count != 0))
        $fatal(3, "invalid or ambiguous switch answer was accepted");

    choose_answer(expected_answer);
    if (selected_answer != expected_answer)
        $fatal(4, "shared one-hot selector code did not reach sound quiz");
    pulse_submit();
    if (!feedback_active || !answer_correct ||
        (answered_count != 1) || (correct_count != 1) ||
        (score_percent != 8'd33))
        $fatal(5, "correct pitch answer was not scored once");

    pulse_submit();
    if ((answered_count != 1) || (correct_count != 1))
        $fatal(6, "feedback accepted a repeated submission");

    pulse_advance();
    if (feedback_active || (question_index != 2'd1) ||
        (audio_frequency != 2'd1) ||
        (audio_amplitude != expected_answer) ||
        (audio_waveform != 2'd2))
        $fatal(7, "amplitude question mapping is wrong");

    choose_answer(wrong_choice(expected_answer));
    pulse_submit();
    if (!feedback_active || answer_correct ||
        (answered_count != 2) || (correct_count != 1))
        $fatal(8, "wrong amplitude answer was not recorded");

    pulse_advance();
    if ((question_index != 2'd2) ||
        (audio_frequency != 2'd1) || (audio_amplitude != 2'd1) ||
        (audio_waveform != expected_answer))
        $fatal(9, "waveform question mapping is wrong");

    choose_answer(expected_answer);
    pulse_submit();
    if (!feedback_active || !answer_correct ||
        (answered_count != 3) || (correct_count != 2) ||
        (score_percent != 8'd66) || (star_level != 2'd2))
        $fatal(10, "final sound score summary is wrong");

    pulse_advance();
    if (!game_complete || !game_active || !audio_muted ||
        (correct_count != 2))
        $fatal(11, "completed game did not hold the final score safely");

    pulse_advance();
    if (!game_active || game_complete || (question_index != 0) ||
        (answered_count != 0) || (correct_count != 0))
        $fatal(12, "game restart did not clear the shared score engine");

    pulse_toggle();
    if (game_active)
        $fatal(13, "long-key toggle did not exit the game");
    pulse_toggle();
    lab_active = 1'b0;
    repeat (2) @(negedge clk);
    if (game_active)
        $fatal(14, "leaving SOUND_LAB did not stop the game");

    $display("TEST_PASS tb_sound_quiz_game");
    $finish;
end

initial begin
    #20_000;
    $fatal(15, "timeout");
end

endmodule
