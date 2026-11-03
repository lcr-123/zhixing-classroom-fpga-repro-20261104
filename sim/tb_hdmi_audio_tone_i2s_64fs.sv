`timescale 1ns/1ps

module tb_hdmi_audio_tone_i2s_64fs;

reg clk;
reg rst;
reg lab_active;
reg [1:0] lab_frequency;
reg [1:0] lab_amplitude;
reg [1:0] lab_waveform;
reg lab_muted;
reg song_enable;
reg control_toggle;
reg [2:0] voice_volume;
reg voice_volume_toggle;
reg practice_prev_tone_toggle;
reg practice_next_tone_toggle;
reg voice_start_toggle;
reg voice_end_toggle;
reg [1:0] voice_clip_index;
wire [7:0] voice_fifo_data;
wire voice_fifo_valid;
wire voice_fifo_empty;
wire voice_fifo_read;
wire voice_subtitle_active;
wire [1:0] voice_subtitle_clip;
wire [4:0] voice_subtitle_cue;
wire voice_subtitle_toggle;
wire i2s_bclk;
wire i2s_lrck;
wire i2s_dout;

integer mclk_cycles;
integer last_frame_cycle;
integer sample_value;
integer previous_value;
integer max_abs;
integer abs_value;
integer sign_changes;
integer distinct_steps;
integer zero_count;
integer i;
integer start_event;
integer voice_supply_index;
integer voice_supply_count;
integer voice_read_pulses;
integer voice_first_read_cycle;
integer voice_second_read_cycle;
integer voice_count_after_first_read;
reg [31:0] low_song_inc;
reg [31:0] base_song_inc;
reg [31:0] high_song_inc;
reg [31:0] practice_phase_before;

hdmi_audio_tone_i2s_64fs #(
    .SONG_TICK_FRAMES(8),
    .SONG_GAP_FRAMES(2),
    .VOICE_SUBTITLE_SAMPLES_PER_TENTH(1),
    .PRACTICE_TONE_SAMPLES(96)
) dut (
    .I_mclk(clk),
    .I_rst(rst),
    .I_lab_active(lab_active),
    .I_lab_frequency(lab_frequency),
    .I_lab_amplitude(lab_amplitude),
    .I_lab_waveform(lab_waveform),
    .I_lab_muted(lab_muted),
    .I_song_enable(song_enable),
    .I_lab_control_toggle(control_toggle),
    .I_voice_volume(voice_volume),
    .I_voice_volume_toggle(voice_volume_toggle),
    .I_practice_prev_tone_toggle(practice_prev_tone_toggle),
    .I_practice_next_tone_toggle(practice_next_tone_toggle),
    .I_boot_success_tone_toggle(1'b0),
    .I_voice_start_toggle(voice_start_toggle),
    .I_voice_end_toggle(voice_end_toggle),
    .I_voice_stop_toggle(1'b0),
    .O_voice_sample_accept(),
    .O_voice_source_step(),
    .I_voice_clip_index(voice_clip_index),
    .I_voice_fifo_data(voice_fifo_data),
    .I_voice_fifo_speed(2'd3),
    .I_voice_fifo_valid(voice_fifo_valid),
    .I_voice_fifo_empty(voice_fifo_empty),
    .I_voice_played_to_end(1'b0),
    .O_voice_fifo_read(voice_fifo_read),
    .O_voice_subtitle_active(voice_subtitle_active),
    .O_voice_subtitle_clip(voice_subtitle_clip),
    .O_voice_subtitle_cue(voice_subtitle_cue),
    .O_voice_subtitle_toggle(voice_subtitle_toggle),
    .O_i2s_BCLK(i2s_bclk),
    .O_i2s_LRCK(i2s_lrck),
    .O_i2s_DOUT(i2s_dout)
);

always #5 clk = ~clk;

assign voice_fifo_empty = (voice_supply_index >= voice_supply_count);
// Match the actual generated asynchronous FIFO: in show-ahead/NOREG mode,
// valid stays high for the entire non-empty interval and dout continuously
// exposes the current head.  It is not a one-cycle read-response pulse.
assign voice_fifo_valid = !voice_fifo_empty;
assign voice_fifo_data =
    (voice_supply_index == 0) ? 8'h20 :
    (voice_supply_index == 1) ? 8'he0 :
    (voice_supply_index == 2) ? 8'h40 : 8'hc0;

always @(posedge clk) begin
    if (voice_fifo_read && !voice_fifo_empty) begin
        voice_supply_index <= voice_supply_index + 1;
        voice_read_pulses <= voice_read_pulses + 1;
        if (voice_read_pulses == 0)
            voice_first_read_cycle <= mclk_cycles;
        if (voice_read_pulses == 1)
            voice_second_read_cycle <= mclk_cycles;
    end
end

always @(posedge clk) begin
    if (rst)
        mclk_cycles <= 0;
    else
        mclk_cycles <= mclk_cycles + 1;
end

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

task get_frame_sample;
    output integer value;
begin : wait_for_frame
    forever begin
        @(posedge clk);
        if ((dut.O_i2s_BCLK == 1'b1) &&
            (dut.S_bit_cnt == 6'd63) &&
            (dut.O_i2s_LRCK == 1'b1)) begin
            #1;
            value = $signed(dut.S_sample_word);
            disable wait_for_frame;
        end
    end
end
endtask

task wait_frames;
    input integer count;
    integer j;
    integer ignored;
begin
    for (j = 0; j < count; j = j + 1)
        get_frame_sample(ignored);
end
endtask

task publish_control;
    input active_value;
    input [1:0] frequency_value;
    input [1:0] amplitude_value;
    input [1:0] waveform_value;
    input muted_value;
    input song_value;
begin
    @(negedge clk);
    lab_active = active_value;
    lab_frequency = frequency_value;
    lab_amplitude = amplitude_value;
    lab_waveform = waveform_value;
    lab_muted = muted_value;
    song_enable = song_value;
    control_toggle = ~control_toggle;
end
endtask

function integer magnitude;
    input integer value;
begin
    magnitude = (value < 0) ? -value : value;
end
endfunction

initial begin
    clk = 1'b0;
    rst = 1'b1;
    lab_active = 1'b0;
    lab_frequency = 2'd0;
    lab_amplitude = 2'd1;
    lab_waveform = 2'd0;
    lab_muted = 1'b0;
    song_enable = 1'b0;
    control_toggle = 1'b0;
    voice_volume = 3'd4;
    voice_volume_toggle = 1'b0;
    practice_prev_tone_toggle = 1'b0;
    practice_next_tone_toggle = 1'b0;
    voice_start_toggle = 1'b0;
    voice_end_toggle = 1'b0;
    voice_clip_index = 2'd0;
    voice_supply_index = 0;
    voice_supply_count = 0;
    voice_read_pulses = 0;
    voice_first_read_cycle = 0;
    voice_second_read_cycle = 0;
    mclk_cycles = 0;
    last_frame_cycle = 0;

    repeat (4) @(negedge clk);
    rst = 1'b0;

    // The established 64fs format must keep exactly 256 mclk cycles/stereo frame.
    get_frame_sample(sample_value);
    last_frame_cycle = mclk_cycles;
    get_frame_sample(sample_value);
    check_equal((mclk_cycles - last_frame_cycle) == 256,
                "stereo sample cadence is not mclk/256 (48 kHz at 12.288 MHz)");
    wait_frames(4);
    check_equal(sample_value == 0,
                "idle audio is not silent outside SOUND_LAB");

    // Practice navigation uses two bounded, click-tapered cues. A boundary
    // press is filtered by the controller, so each mailbox token here must
    // create exactly one complete 96-frame cue.
    @(negedge clk);
    practice_prev_tone_toggle = ~practice_prev_tone_toggle;
    wait (dut.S_practice_tone_active);
    check_equal(!dut.S_practice_tone_direction,
                "previous-page cue direction was not latched");
    get_frame_sample(sample_value);
    max_abs = magnitude(sample_value);
    practice_phase_before = dut.S_practice_tone_phase;
    get_frame_sample(sample_value);
    abs_value = magnitude(sample_value);
    if (abs_value > max_abs)
        max_abs = abs_value;
    check_equal((dut.S_practice_tone_phase - practice_phase_before) ==
                32'd80530637,
                "previous-page cue is not 900 Hz");
    for (i = 0; i < 94; i = i + 1) begin
        get_frame_sample(sample_value);
        abs_value = magnitude(sample_value);
        if (abs_value > max_abs)
            max_abs = abs_value;
    end
    check_equal((max_abs >= 3600000) && (max_abs <= 4000000),
                "previous-page cue did not reach its boosted PCM level");
    wait (!dut.S_practice_tone_active);
    check_equal((dut.S_practice_tone_count == 0) &&
                (dut.S_practice_tone_phase == 0),
                "previous-page cue did not stop at its bounded duration");

    @(negedge clk);
    practice_next_tone_toggle = ~practice_next_tone_toggle;
    wait (dut.S_practice_tone_active);
    check_equal(dut.S_practice_tone_direction,
                "next-page cue direction was not latched");
    get_frame_sample(sample_value);
    max_abs = magnitude(sample_value);
    practice_phase_before = dut.S_practice_tone_phase;
    get_frame_sample(sample_value);
    abs_value = magnitude(sample_value);
    if (abs_value > max_abs)
        max_abs = abs_value;
    check_equal((dut.S_practice_tone_phase - practice_phase_before) ==
                32'd107374182,
                "next-page cue is not 1.2 kHz");
    for (i = 0; i < 94; i = i + 1) begin
        get_frame_sample(sample_value);
        abs_value = magnitude(sample_value);
        if (abs_value > max_abs)
            max_abs = abs_value;
    end
    check_equal((max_abs >= 1800000) && (max_abs <= 2000000),
                "next-page cue PCM level changed unexpectedly");
    wait (!dut.S_practice_tone_active);

    // Free sound-lab mode is a sequenced F-major Xiao Luo Hao teaching
    // melody.  It must advance notes, create short articulation gaps and
    // retain exact octave transposition without affecting quiz test tones.
    publish_control(1'b1, 2'd1, 2'd2, 2'd0, 1'b0, 1'b1);
    wait_frames(72);
    start_event = dut.S_song_event_idx;
    zero_count = 0;
    for (i = 0; i < 40; i = i + 1) begin
        get_frame_sample(sample_value);
        if (sample_value == 0)
            zero_count = zero_count + 1;
    end
    check_equal(dut.S_song_event_idx != start_event,
                "Xiao Luo Hao sequencer did not advance events");
    check_equal(zero_count >= 2,
                "song articulation did not insert note gaps");
    low_song_inc = dut.song_note_inc(dut.W_song_note, 2'd0);
    base_song_inc = dut.song_note_inc(dut.W_song_note, 2'd1);
    high_song_inc = dut.song_note_inc(dut.W_song_note, 2'd2);
    check_equal((base_song_inc - (low_song_inc << 1)) <= 1,
                "low song octave is not one half of original");
    check_equal(high_song_inc == (base_song_inc << 1),
                "high song octave is not twice original");

    // Lesson narration overrides the melody, expands signed 8-bit PCM to
    // 24-bit samples and consumes exactly one byte per three output frames.
    voice_supply_index = 0;
    voice_supply_count = 150;
    voice_read_pulses = 0;
    voice_clip_index = 2'd2;
    @(negedge clk);
    voice_start_toggle = ~voice_start_toggle;
    wait (dut.S_voice_active);
    repeat (3) @(posedge clk);
    check_equal(dut.S_voice_active && (dut.S_voice_clip == 2'd2),
                "lesson narration did not become the active audio source");
    check_equal(voice_subtitle_active &&
                 (voice_subtitle_clip == 2'd2) &&
                (voice_subtitle_cue == 5'd0),
                "lesson subtitle did not start with the narration clip");
    wait (voice_read_pulses >= 1);
    repeat (3) @(posedge clk);
    check_equal(dut.S_voice_sample == 24'sh200000,
                "signed 8-bit lesson PCM was not expanded to 24 bits");
    check_equal(dut.S_voice_volume_gain == 6'd32,
                "lesson narration did not start at full volume");
    wait (voice_read_pulses >= 1);
    repeat (4) @(posedge clk);
    voice_count_after_first_read = dut.S_voice_sample_count;
    check_equal(voice_count_after_first_read == 1,
                "show-ahead FIFO valid level was counted as repeated PCM samples");
    repeat (64) @(posedge clk);
    check_equal(dut.S_voice_sample_count == voice_count_after_first_read,
                "subtitle sample count advanced without an accepted FIFO read");
    wait (voice_read_pulses >= 2);
    check_equal((voice_second_read_cycle - voice_first_read_cycle) == 768,
                "16 kHz lesson FIFO cadence is not one byte per three frames");
    wait (voice_subtitle_cue == 5'd1);
    check_equal(dut.S_voice_sample_count >= 20'd75,
                "subtitle cue advanced before consumed PCM threshold");
    wait (dut.S_voice_sample_count == 20'd115);
    #1;
    check_equal(voice_subtitle_cue == 5'd2,
                "nature lesson subtitle skipped the first question");
    wait (voice_subtitle_cue == 5'd3);
    check_equal(dut.S_voice_sample_count >= 20'd126,
                "nature lesson second question did not start on time");

    // A navigation cue arriving during narration remains pending: speech is
    // selected first and the bounded cue envelope does not advance underneath.
    @(negedge clk);
    practice_next_tone_toggle = ~practice_next_tone_toggle;
    wait (dut.S_practice_tone_active);
    wait_frames(4);
    check_equal(dut.S_practice_tone_count == 0,
                "practice cue advanced while narration had priority");
    check_equal($signed(dut.W_selected_sample) ==
                $signed(dut.W_voice_scaled_sample),
                "practice cue interrupted lesson narration");

    // Level zero must mute PCM while real FIFO consumption/cues continue.
    @(negedge clk);
    voice_volume = 3'd0;
    voice_volume_toggle = ~voice_volume_toggle;
    wait (dut.S_voice_volume_target == 0);
    wait (dut.S_voice_volume_gain == 0);
    #1;
    check_equal($signed(dut.W_voice_scaled_sample) == 0,
                "zero volume did not mute narration PCM");

    // A learning-page volume command crosses through its own stable mailbox
    // and ramps to 25 percent without disturbing FIFO cadence or subtitles.
    @(negedge clk);
    voice_volume = 3'd1;
    voice_volume_toggle = ~voice_volume_toggle;
    wait (dut.S_voice_volume_target == 6'd8);
    wait (dut.S_voice_volume_gain == 6'd8);
    #1;
    check_equal($signed(dut.W_voice_scaled_sample) ==
                ($signed(dut.S_voice_sample) >>> 2),
                "lowest lesson volume is not 25 percent");
    @(negedge clk);
    voice_volume = 3'd2;
    voice_volume_toggle = ~voice_volume_toggle;
    wait (dut.S_voice_volume_target == 6'd16);
    wait (dut.S_voice_volume_gain == 6'd16);
    #1;
    check_equal($signed(dut.W_voice_scaled_sample) ==
                ($signed(dut.S_voice_sample) >>> 1),
                "second lesson volume is not 50 percent");
    @(negedge clk);
    voice_volume = 3'd3;
    voice_volume_toggle = ~voice_volume_toggle;
    wait (dut.S_voice_volume_target == 6'd24);
    wait (dut.S_voice_volume_gain == 6'd24);
    #1;
    check_equal($signed(dut.W_voice_scaled_sample) ==
                (($signed(dut.S_voice_sample) >>> 1) +
                 ($signed(dut.S_voice_sample) >>> 2)),
                "third lesson volume is not 75 percent");
    @(negedge clk);
    voice_volume = 3'd4;
    voice_volume_toggle = ~voice_volume_toggle;
    wait (dut.S_voice_volume_target == 6'd32);
    wait (dut.S_voice_volume_gain == 6'd32);
    wait (voice_fifo_empty);
    @(negedge clk);
    voice_end_toggle = ~voice_end_toggle;
    wait (!dut.S_voice_active);
    check_equal(!voice_subtitle_active,
                "lesson subtitle remained active after narration drained");
    check_equal((dut.S_song_event_idx == 0) &&
                (dut.S_song_tick_count == 0),
                "melody did not restart from the beginning after narration");
    wait (!dut.S_practice_tone_active);

    // High-amplitude 500 Hz square wave: 192 samples contain about four edges.
    publish_control(1'b1, 2'd0, 2'd2, 2'd0, 1'b0, 1'b0);
    wait_frames(72);
    sign_changes = 0;
    max_abs = 0;
    get_frame_sample(previous_value);
    for (i = 0; i < 192; i = i + 1) begin
        get_frame_sample(sample_value);
        abs_value = magnitude(sample_value);
        if (abs_value > max_abs)
            max_abs = abs_value;
        if (((sample_value < 0) && (previous_value >= 0)) ||
            ((sample_value >= 0) && (previous_value < 0)))
            sign_changes = sign_changes + 1;
        previous_value = sample_value;
    end
    check_equal(max_abs == 2000000,
                "high square-wave amplitude is wrong");
    check_equal((sign_changes >= 3) && (sign_changes <= 5),
                "500 Hz square-wave edge count is wrong");

    // Low amplitude must be exactly one quarter of high amplitude after fade.
    publish_control(1'b1, 2'd0, 2'd0, 2'd0, 1'b0, 1'b0);
    wait_frames(72);
    max_abs = 0;
    for (i = 0; i < 32; i = i + 1) begin
        get_frame_sample(sample_value);
        abs_value = magnitude(sample_value);
        if (abs_value > max_abs)
            max_abs = abs_value;
    end
    check_equal(max_abs == 500000,
                "low amplitude is not one quarter of high amplitude");

    // At 2 kHz there are about eight sign edges in 96 samples.
    publish_control(1'b1, 2'd2, 2'd2, 2'd0, 1'b0, 1'b0);
    wait_frames(72);
    sign_changes = 0;
    get_frame_sample(previous_value);
    for (i = 0; i < 96; i = i + 1) begin
        get_frame_sample(sample_value);
        if (((sample_value < 0) && (previous_value >= 0)) ||
            ((sample_value >= 0) && (previous_value < 0)))
            sign_changes = sign_changes + 1;
        previous_value = sample_value;
    end
    check_equal((sign_changes >= 7) && (sign_changes <= 9),
                "2 kHz square-wave edge count is wrong");

    // A waveform switch must pass through a zero-gain sample before recovery.
    publish_control(1'b1, 2'd2, 2'd2, 2'd1, 1'b0, 1'b0);
    zero_count = 0;
    for (i = 0; i < 72; i = i + 1) begin
        get_frame_sample(sample_value);
        if (sample_value == 0)
            zero_count = zero_count + 1;
    end
    check_equal(zero_count >= 1,
                "control transition did not fade through zero");

    // Triangle and LUT sine must contain many distinct levels and stay bounded.
    distinct_steps = 0;
    max_abs = 0;
    get_frame_sample(previous_value);
    for (i = 0; i < 48; i = i + 1) begin
        get_frame_sample(sample_value);
        if (sample_value != previous_value)
            distinct_steps = distinct_steps + 1;
        abs_value = magnitude(sample_value);
        if (abs_value > max_abs)
            max_abs = abs_value;
        previous_value = sample_value;
    end
    check_equal((distinct_steps >= 40) && (max_abs <= 2097152),
                "triangle waveform shape/range is wrong");

    publish_control(1'b1, 2'd1, 2'd2, 2'd2, 1'b0, 1'b0);
    wait_frames(72);
    distinct_steps = 0;
    max_abs = 0;
    get_frame_sample(previous_value);
    for (i = 0; i < 48; i = i + 1) begin
        get_frame_sample(sample_value);
        if (sample_value != previous_value)
            distinct_steps = distinct_steps + 1;
        abs_value = magnitude(sample_value);
        if (abs_value > max_abs)
            max_abs = abs_value;
        previous_value = sample_value;
    end
    check_equal((distinct_steps >= 20) && (max_abs == 2000000),
                "sine lookup waveform shape/range is wrong");

    publish_control(1'b1, 2'd1, 2'd2, 2'd2, 1'b1, 1'b0);
    wait_frames(72);
    for (i = 0; i < 16; i = i + 1) begin
        get_frame_sample(sample_value);
        check_equal(sample_value == 0, "mute did not produce zero PCM");
    end

    // Leaving SOUND_LAB must stay quiet; the former repeating acceptance
    // scale was audible as an unwanted ding-ding-ding background sound.
    publish_control(1'b0, 2'd1, 2'd1, 2'd0, 1'b0, 1'b0);
    wait_frames(72);
    get_frame_sample(sample_value);
    check_equal(sample_value == 0,
                "unwanted acceptance tone resumed after SOUND_LAB");

    $display("TEST_PASS: hdmi_audio_tone_i2s_64fs");
    $finish;
end

endmodule
