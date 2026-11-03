`timescale 1ns/1ps
module tb_boot_success_tone;
    localparam [3:0] APP_ST_BOOT_SELFTEST = 4'd0;
    localparam [3:0] APP_ST_HOME = 4'd1;
    localparam [3:0] APP_ST_SETTINGS = 4'd7;
    reg clk = 0, audio_mclk = 0, rst_ref = 1, rst_audio = 1;
    reg [3:0] learn_state = APP_ST_BOOT_SELFTEST;
    reg content_ready_ref_sync = 0;
    reg boot_success_tone_toggle_ref;
    reg boot_success_tone_sent_ref;
    wire bclk, lrck, dout;
    integer starts = 0, frames = 0, audible = 0;
    integer first_cycle = 0, last_cycle = 0, audio_cycles = 0;
    reg was_active = 0;

    always #10 clk = ~clk;
    always #5 audio_mclk = ~audio_mclk;
    `include "out/boot_success_tone/top_event.vh"

    hdmi_audio_tone_i2s_64fs dut (
        .I_mclk(audio_mclk), .I_rst(rst_audio),
        .I_lab_active(1'b0), .I_lab_frequency(2'd0),
        .I_lab_amplitude(2'd1), .I_lab_waveform(2'd0),
        .I_lab_muted(1'b0), .I_song_enable(1'b0),
        .I_lab_control_toggle(1'b0), .I_voice_volume(3'd4),
        .I_voice_volume_toggle(1'b0),
        .I_practice_prev_tone_toggle(1'b0),
        .I_practice_next_tone_toggle(1'b0),
        .I_boot_success_tone_toggle(boot_success_tone_toggle_ref),
        .I_voice_start_toggle(1'b0), .I_voice_end_toggle(1'b0),
        .I_voice_stop_toggle(1'b0), .I_voice_clip_index(2'd0),
        .I_voice_fifo_data(8'd0), .I_voice_fifo_speed(2'd3),
        .I_voice_fifo_valid(1'b0), .I_voice_fifo_empty(1'b1),
        .I_voice_played_to_end(1'b0), .O_voice_fifo_read(),
        .O_voice_sample_accept(), .O_voice_source_step(),
        .O_voice_subtitle_active(), .O_voice_subtitle_clip(),
        .O_voice_subtitle_cue(), .O_voice_subtitle_toggle(),
        .O_i2s_BCLK(bclk), .O_i2s_LRCK(lrck), .O_i2s_DOUT(dout)
    );

    always @(posedge audio_mclk) begin
        audio_cycles <= audio_cycles + 1;
        if (dut.S_boot_tone_active && !was_active) begin
            starts <= starts + 1;
            first_cycle <= audio_cycles;
        end
        was_active <= dut.S_boot_tone_active;
        if (dut.S_boot_tone_active && bclk && dut.S_bit_cnt == 6'd63 && lrck) begin
            frames <= frames + 1;
            if (dut.S_boot_tone_count >= 16'd33 &&
                dut.S_boot_tone_count < 16'd47968 &&
                dut.S_sample_word != 0)
                audible <= audible + 1;
        end
        if (!dut.S_boot_tone_active && was_active)
            last_cycle <= audio_cycles;
    end

    initial begin
        repeat (5) @(negedge clk);
        rst_ref = 0;
        rst_audio = 0;
        repeat (20) @(negedge clk);
        if (starts != 0 || boot_success_tone_sent_ref)
            $fatal(1, "startup sound before successful boot");
        learn_state = APP_ST_HOME;
        repeat (20) @(negedge clk);
        if (starts != 0 || boot_success_tone_sent_ref)
            $fatal(1, "HOME without ready triggered sound");
        content_ready_ref_sync = 1;
        wait (starts == 1);
        wait (!dut.S_boot_tone_active);
        repeat (256) @(negedge audio_mclk);
        if (frames != 48000 ||
            last_cycle - first_cycle <= 47999 * 256 ||
            last_cycle - first_cycle > 48000 * 256 ||
            audible < 40000 || dut.S_sample_word != 0)
            $fatal(1, "48 kHz startup tone duration/cadence/PCM incorrect: frames=%0d cycles=%0d audible=%0d sample=%0d",
                   frames, last_cycle-first_cycle, audible, dut.S_sample_word);
        learn_state = APP_ST_SETTINGS;
        repeat (8) @(negedge clk);
        learn_state = APP_ST_HOME;
        repeat (300) @(negedge audio_mclk);
        if (starts != 1 || !boot_success_tone_sent_ref)
            $fatal(1, "return HOME replayed startup sound");
        rst_ref = 1;
        rst_audio = 1;
        learn_state = APP_ST_BOOT_SELFTEST;
        content_ready_ref_sync = 0;
        repeat (5) @(negedge clk);
        rst_ref = 0;
        rst_audio = 0;
        repeat (8) @(negedge clk);
        if (boot_success_tone_sent_ref)
            $fatal(1, "reset did not rearm startup sound");
        content_ready_ref_sync = 1;
        learn_state = APP_ST_HOME;
        wait (starts == 2);
        $display("TEST_PASS boot-success one-shot 48000 frames, 48 kHz stereo cadence, reset rearm");
        $finish;
    end
    initial begin
        #200000000;
        $fatal(1, "startup tone watchdog");
    end
endmodule
