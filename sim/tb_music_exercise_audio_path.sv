`timescale 1ns/1ps

// Application-to-HDMI-input audio path for the ordinary page-08 music quiz.
// This deliberately crosses the same control mailbox and I2S receiver used by
// the board design so a non-zero internal DDS value alone cannot pass the test.
module tb_music_exercise_audio_path;

reg ref_clk;
reg audio_mclk;
reg video_clk;
reg rst_ref;
reg rst_audio;
reg rst_video;
reg music_quiz_request;

wire       lab_active;
wire [1:0] frequency_select;
wire [1:0] amplitude_level;
wire [1:0] waveform_select;
wire       muted;
wire       song_enable;
wire       control_toggle;
wire       i2s_bclk;
wire       i2s_lrck;
wire       i2s_dout;
wire       audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire       acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

integer valid_count;
integer nonzero_count;
integer acr_count;
integer max_abs;
integer sample_value;
integer sample_abs;

always #10.000 ref_clk = ~ref_clk;       // 50 MHz
always #40.690 audio_mclk = ~audio_mclk; // approximately 12.288 MHz
always #6.734 video_clk = ~video_clk;    // approximately 74.25 MHz

sound_lab_control u_control (
    .clk                   (ref_clk),
    .rst                   (rst_ref),
    .lab_active_request    (music_quiz_request),
    .switch_async          (4'b0000),
    .amplitude_cycle_pulse (1'b0),
    .mute_toggle_pulse     (1'b0),
    .quiz_active           (music_quiz_request),
    .quiz_frequency        (2'd2),
    .quiz_amplitude        (2'd2),
    .quiz_waveform         (2'd0),
    .quiz_muted            (1'b0),
    .quiz_song_enable      (music_quiz_request),
    .lab_active            (lab_active),
    .frequency_select      (frequency_select),
    .amplitude_level       (amplitude_level),
    .waveform_select       (waveform_select),
    .muted                 (muted),
    .song_enable           (song_enable),
    .control_toggle        (control_toggle)
);

hdmi_audio_tone_i2s_64fs #(
    .SONG_TICK_FRAMES (8),
    .SONG_GAP_FRAMES  (2)
) u_tone (
    .I_mclk                  (audio_mclk),
    .I_rst                   (rst_audio),
    .I_lab_active            (lab_active),
    .I_lab_frequency         (frequency_select),
    .I_lab_amplitude         (amplitude_level),
    .I_lab_waveform          (waveform_select),
    .I_lab_muted             (muted),
    .I_song_enable           (song_enable),
    .I_lab_control_toggle    (control_toggle),
    .I_voice_volume          (3'd4),
    .I_voice_volume_toggle   (1'b0),
    .I_practice_prev_tone_toggle(1'b0),
    .I_practice_next_tone_toggle(1'b0),
    .I_boot_success_tone_toggle(1'b0),
    .I_voice_start_toggle    (1'b0),
    .I_voice_end_toggle      (1'b0),
    .I_voice_stop_toggle(1'b0),
    .O_voice_sample_accept(),
    .O_voice_source_step(),
    .I_voice_clip_index      (2'd0),
    .I_voice_fifo_data       (8'd0),
    .I_voice_fifo_speed      (2'd3),
    .I_voice_fifo_valid      (1'b0),
    .I_voice_fifo_empty      (1'b1),
    .I_voice_played_to_end   (1'b0),
    .O_voice_fifo_read       (),
    .O_voice_subtitle_active (),
    .O_voice_subtitle_clip   (),
    .O_voice_subtitle_cue    (),
    .O_voice_subtitle_toggle (),
    .O_i2s_BCLK              (i2s_bclk),
    .O_i2s_LRCK              (i2s_lrck),
    .O_i2s_DOUT              (i2s_dout)
);

I2S_receiver u_receiver (
    .I_clk              (video_clk),
    .I_rst              (rst_video),
    .I_i2s_BCLK         (i2s_bclk),
    .I_i2s_LRCK         (i2s_lrck),
    .I_i2s_DOUT         (i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

audio_arc_calculate u_acr (
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

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

always @(posedge video_clk) begin
    if (audio_valid) begin
        valid_count = valid_count + 1;
        sample_value = $signed(audio_left_data);
        sample_abs = (sample_value < 0) ? -sample_value : sample_value;
        if (sample_abs > max_abs)
            max_abs = sample_abs;
        if (sample_value != 0)
            nonzero_count = nonzero_count + 1;
        check_equal(audio_left_data == audio_right_data,
                    "HDMI PCM channels differ for mono quiz melody");
    end
    if (acr_valid) begin
        acr_count = acr_count + 1;
        check_equal(acr_n == 20'd6144,
                    "ACR N is not the established 48 kHz value");
        check_equal(acr_cts != 20'd0,
                    "ACR CTS is zero on a valid pulse");
    end
end

initial begin
    ref_clk = 1'b0;
    audio_mclk = 1'b0;
    video_clk = 1'b0;
    rst_ref = 1'b1;
    rst_audio = 1'b1;
    rst_video = 1'b1;
    music_quiz_request = 1'b0;
    valid_count = 0;
    nonzero_count = 0;
    acr_count = 0;
    max_abs = 0;
    sample_value = 0;
    sample_abs = 0;

    #500;
    rst_ref = 1'b0;
    rst_audio = 1'b0;
    rst_video = 1'b0;
    #500;

    // This rising level is the exact page-08 request presented by the top.
    music_quiz_request = 1'b1;

    wait (valid_count >= 200);
    $display("PAGE08_AUDIO_STATS valid=%0d nonzero=%0d max_abs=%0d acr=%0d event=%0d",
             valid_count, nonzero_count, max_abs, acr_count,
             u_tone.S_song_event_idx);
    check_equal(lab_active && !muted && song_enable,
                "page-08 request did not select the Xiao Luo Hao sequencer");
    check_equal((frequency_select == 2'd2) &&
                (amplitude_level == 2'd2) &&
                (waveform_select == 2'd0),
                "page-08 request did not publish high square-wave melody settings");
    check_equal(u_tone.S_song_event_idx != 6'd0,
                "Xiao Luo Hao melody sequencer did not advance");
    check_equal(nonzero_count >= 80,
                "I2S receiver did not deliver sustained non-zero HDMI PCM");
    check_equal(max_abs >= 1500000,
                "received page-08 PCM is below the intended high level");
    check_equal(acr_count >= 3,
                "ACR cadence did not accompany the quiz PCM stream");

    music_quiz_request = 1'b0;
    repeat (100) @(posedge video_clk);
    check_equal(!lab_active,
                "page-08 audio did not deactivate after leaving the question");

    $display("TEST_PASS: music_exercise_audio_path valid=%0d nonzero=%0d max_abs=%0d acr=%0d",
             valid_count, nonzero_count, max_abs, acr_count);
    $finish;
end

initial begin
    #20000000;
    $display("TEST_FAIL: music exercise audio path timeout");
    $fatal(1);
end

endmodule
