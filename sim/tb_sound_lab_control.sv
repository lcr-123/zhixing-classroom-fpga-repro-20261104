`timescale 1ns/1ps

module tb_sound_lab_control;

reg clk;
reg rst;
reg lab_active_request;
reg [3:0] switch_async;
reg amplitude_cycle_pulse;
reg mute_toggle_pulse;
reg quiz_active;
reg [1:0] quiz_frequency;
reg [1:0] quiz_amplitude;
reg [1:0] quiz_waveform;
reg quiz_muted;
reg quiz_song_enable;
wire lab_active;
wire [1:0] frequency_select;
wire [1:0] amplitude_level;
wire [1:0] waveform_select;
wire muted;
wire song_enable;
wire control_toggle;

sound_lab_control dut (
    .clk(clk),
    .rst(rst),
    .lab_active_request(lab_active_request),
    .switch_async(switch_async),
    .amplitude_cycle_pulse(amplitude_cycle_pulse),
    .mute_toggle_pulse(mute_toggle_pulse),
    .quiz_active(quiz_active),
    .quiz_frequency(quiz_frequency),
    .quiz_amplitude(quiz_amplitude),
    .quiz_waveform(quiz_waveform),
    .quiz_muted(quiz_muted),
    .quiz_song_enable(quiz_song_enable),
    .lab_active(lab_active),
    .frequency_select(frequency_select),
    .amplitude_level(amplitude_level),
    .waveform_select(waveform_select),
    .muted(muted),
    .song_enable(song_enable),
    .control_toggle(control_toggle)
);

always #5 clk = ~clk;

task check_equal;
    input condition;
    input [8*96-1:0] message;
begin
    if (!condition) begin
        $display("TEST_FAIL: %0s", message);
        $fatal(1);
    end
end
endtask

task pulse_amplitude;
begin
    @(negedge clk);
    amplitude_cycle_pulse = 1'b1;
    @(negedge clk);
    amplitude_cycle_pulse = 1'b0;
    @(negedge clk);
end
endtask

task pulse_mute;
begin
    @(negedge clk);
    mute_toggle_pulse = 1'b1;
    @(negedge clk);
    mute_toggle_pulse = 1'b0;
    @(negedge clk);
end
endtask

initial begin
    clk = 1'b0;
    rst = 1'b1;
    lab_active_request = 1'b0;
    switch_async = 4'b0000;
    amplitude_cycle_pulse = 1'b0;
    mute_toggle_pulse = 1'b0;
    quiz_active = 1'b0;
    quiz_frequency = 2'd0;
    quiz_amplitude = 2'd0;
    quiz_waveform = 2'd0;
    quiz_muted = 1'b0;
    quiz_song_enable = 1'b0;

    repeat (3) @(negedge clk);
    rst = 1'b0;

    // SW1 high preloads 1 kHz while inactive without publishing a mailbox.
    switch_async = 4'b0001;
    repeat (4) @(negedge clk);
    check_equal((frequency_select == 2'd1) &&
                (waveform_select == 2'd0),
                "inactive switch preload is wrong");
    check_equal(control_toggle == 1'b0,
                "inactive switch unexpectedly published a mailbox");

    lab_active_request = 1'b1;
    repeat (2) @(negedge clk);
    check_equal(lab_active && song_enable &&
                (amplitude_level == 2'd1) && !muted,
                "sound lab did not enter with deterministic defaults");
    check_equal(control_toggle == 1'b1,
                "sound-lab entry did not publish a mailbox");

    pulse_amplitude();
    check_equal((amplitude_level == 2'd2) &&
                (control_toggle == 1'b0),
                "amplitude did not advance to high");
    pulse_amplitude();
    check_equal((amplitude_level == 2'd0) &&
                (control_toggle == 1'b1),
                "amplitude did not wrap to low");
    pulse_amplitude();
    check_equal((amplitude_level == 2'd1) &&
                (control_toggle == 1'b0),
                "amplitude did not return to middle");

    pulse_mute();
    check_equal(muted && (control_toggle == 1'b1),
                "mute did not toggle on");

    // Quiz mode overrides one complete sound-control word. Free-mode changes
    // stay private until the learner exits the listening game.
    quiz_frequency = 2'd2;
    quiz_amplitude = 2'd0;
    quiz_waveform = 2'd1;
    quiz_muted = 1'b0;
    quiz_active = 1'b1;
    repeat (3) @(negedge clk);
    check_equal((frequency_select == 2'd2) &&
                (amplitude_level == 2'd0) &&
                (waveform_select == 2'd1) && !muted && !song_enable,
                "quiz override did not publish atomically");

    // The paired page-08 exercise reuses the same atomic override but enables
    // the Xiao Luo Hao sequencer instead of a fixed single tone.
    quiz_song_enable = 1'b1;
    repeat (3) @(negedge clk);
    check_equal(song_enable,
                "paired music exercise did not enable the song sequencer");
    quiz_song_enable = 1'b0;
    repeat (3) @(negedge clk);
    check_equal(!song_enable,
                "dynamic listening quiz did not restore fixed-tone mode");

    switch_async = 4'b0000;
    amplitude_cycle_pulse = 1'b1;
    mute_toggle_pulse = 1'b1;
    @(negedge clk);
    amplitude_cycle_pulse = 1'b0;
    mute_toggle_pulse = 1'b0;
    repeat (3) @(negedge clk);
    check_equal((frequency_select == 2'd2) &&
                (amplitude_level == 2'd0) &&
                (waveform_select == 2'd1) && !muted,
                "free controls leaked into active quiz audio");

    quiz_active = 1'b0;
    repeat (3) @(negedge clk);
    check_equal((frequency_select == 2'd0) &&
                (amplitude_level == 2'd1) &&
                (waveform_select == 2'd0) && muted && song_enable,
                "free sound settings were not restored after quiz exit");

    // {SW4,SW3}=11 maps safely to sine and {SW2,SW1}=10 to 2 kHz.
    switch_async = 4'b1110;
    repeat (4) @(negedge clk);
    check_equal((frequency_select == 2'd2) &&
                (waveform_select == 2'd2),
                "switch normalization/publish is wrong");
    check_equal(control_toggle == 1'b0,
                "switch change did not publish exactly once");

    // Simultaneous key events have a deterministic amplitude-first priority.
    amplitude_cycle_pulse = 1'b1;
    mute_toggle_pulse = 1'b1;
    @(negedge clk);
    amplitude_cycle_pulse = 1'b0;
    mute_toggle_pulse = 1'b0;
    @(negedge clk);
    check_equal((amplitude_level == 2'd2) && muted,
                "simultaneous key priority is not amplitude-first");
    check_equal(control_toggle == 1'b1,
                "simultaneous keys published more than one update");

    lab_active_request = 1'b0;
    repeat (2) @(negedge clk);
    check_equal(!lab_active && !song_enable &&
                (amplitude_level == 2'd1) && !muted,
                "sound-lab exit did not restore defaults");
    check_equal(control_toggle == 1'b0,
                "sound-lab exit did not publish exactly once");

    pulse_amplitude();
    pulse_mute();
    check_equal((amplitude_level == 2'd1) && !muted &&
                (control_toggle == 1'b0),
                "inactive key pulse changed sound controls");

    $display("TEST_PASS: sound_lab_control");
    $finish;
end

endmodule
