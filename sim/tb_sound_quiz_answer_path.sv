`timescale 1ns/1ps

module tb_sound_quiz_answer_path;

reg clk = 1'b0;
reg rst = 1'b1;
reg lab_active = 1'b0;
reg toggle_game_pulse = 1'b0;
reg key2_short = 1'b0;
reg key4_short = 1'b0;
reg [3:0] switch_async = 4'b0000;

wire game_active;
wire feedback_active;
wire game_complete;
wire answer_page_active;
wire [1:0] selected_answer;
wire switch_selection_active;
wire selection_valid;
wire submit_pulse;
wire advance_pulse;
wire [1:0] question_index;
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
wire [3:0] displayed_choice;

always #5 clk = ~clk;

assign answer_page_active = game_active &&
                            !feedback_active &&
                            !game_complete;
assign submit_pulse = key4_short && answer_page_active &&
                      selection_valid && (selected_answer != 2'd3);
assign advance_pulse = key2_short && game_active &&
                       (feedback_active || game_complete);
assign displayed_choice = (selection_valid &&
                           (selected_answer != 2'd3)) ?
                          ({2'b00, selected_answer} + 4'd1) : 4'he;

learning_answer_input u_answer_input (
    .clk                    (clk),
    .rst                    (rst),
    .answer_page_active     (answer_page_active),
    .cycle_pulse            (key2_short),
    .switch_async           (switch_async),
    .selected_answer        (selected_answer),
    .switch_selection_active(switch_selection_active),
    .selection_valid        (selection_valid)
);

sound_quiz_game u_sound_quiz (
    .clk                (clk),
    .rst                (rst),
    .lab_active         (lab_active),
    .toggle_game_pulse  (toggle_game_pulse),
    .advance_pulse      (advance_pulse),
    .submit_pulse       (submit_pulse),
    .answer_code        (selected_answer),
    .answer_valid       (selection_valid &&
                         (selected_answer != 2'd3)),
    .game_active        (game_active),
    .feedback_active    (feedback_active),
    .game_complete      (game_complete),
    .question_index     (question_index),
    .selected_answer    (),
    .expected_answer    (expected_answer),
    .answer_correct     (answer_correct),
    .answered_count     (answered_count),
    .correct_count      (correct_count),
    .score_percent      (score_percent),
    .star_level         (star_level),
    .audio_frequency    (audio_frequency),
    .audio_amplitude    (audio_amplitude),
    .audio_waveform     (audio_waveform),
    .audio_muted        (audio_muted)
);

task automatic pulse_toggle;
begin
    @(negedge clk); toggle_game_pulse = 1'b1;
    @(negedge clk); toggle_game_pulse = 1'b0;
    repeat (3) @(negedge clk);
end
endtask

task automatic pulse_key2;
begin
    @(negedge clk); key2_short = 1'b1;
    @(negedge clk); key2_short = 1'b0;
    repeat (3) @(negedge clk);
end
endtask

task automatic pulse_key4;
begin
    @(negedge clk); key4_short = 1'b1;
    @(negedge clk); key4_short = 1'b0;
    repeat (3) @(negedge clk);
end
endtask

task automatic publish_switches(input [3:0] value);
begin
    switch_async = value;
    repeat (3) @(posedge clk);
    #1;
end
endtask

initial begin
    repeat (3) @(posedge clk);
    @(negedge clk); rst = 1'b0;
    lab_active = 1'b1;
    pulse_toggle();

    // The exercise card labels its choices A/B/C. SW3 must therefore select
    // C directly, and the visible status digit must change to 3.
    publish_switches(4'b0100);
    if (!selection_valid || !switch_selection_active ||
        (selected_answer != 2'd2) || (displayed_choice != 4'd3))
        $fatal(1, "SW3 did not select visible answer C");
    pulse_key4();
    if (!feedback_active || (answered_count != 4'd1))
        $fatal(2, "valid one-hot answer did not submit");

    pulse_key2();
    if (question_index != 2'd1 || feedback_active)
        $fatal(3, "KEY2 did not advance feedback to the next sound question");

    // Multiple raised switches must show E and KEY4 must be ignored.
    publish_switches(4'b0011);
    if (selection_valid || (displayed_choice != 4'he))
        $fatal(4, "ambiguous sound answer was not rejected visibly");
    pulse_key4();
    if (feedback_active || (answered_count != 4'd1))
        $fatal(5, "ambiguous sound answer reached the scorer");

    // With all switches down, KEY2 retains the familiar cycle fallback.
    publish_switches(4'b0000);
    pulse_key2();
    if (!selection_valid || switch_selection_active ||
        (selected_answer != 2'd1) || (displayed_choice != 4'd2))
        $fatal(6, "KEY2 did not cycle the sound answer to B");
    pulse_key4();
    if (!feedback_active || (answered_count != 4'd2))
        $fatal(7, "KEY2-selected sound answer did not submit");

    $display("TEST_PASS tb_sound_quiz_answer_path");
    $finish;
end

initial begin
    #20_000;
    $fatal(8, "timeout");
end

endmodule
