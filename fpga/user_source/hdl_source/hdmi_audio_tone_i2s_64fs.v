module hdmi_audio_tone_i2s_64fs #(
    parameter integer SONG_TICK_FRAMES = 7200,
    parameter integer SONG_GAP_FRAMES = 720,
    parameter integer VOICE_SUBTITLE_SAMPLES_PER_TENTH = 1600,
    parameter integer PRACTICE_TONE_SAMPLES = 3840,
    parameter integer BOOT_TONE_SAMPLES = 48000
)(
    input  wire       I_mclk,      // 12.288 MHz
    input  wire       I_rst,

    // Stable 50 MHz-domain mailbox data. The toggle is synchronized here;
    // data is sampled only after the two-stage toggle synchronizer settles.
    input  wire       I_lab_active,
    input  wire [1:0] I_lab_frequency,
    input  wire [1:0] I_lab_amplitude,
    input  wire [1:0] I_lab_waveform,
    input  wire       I_lab_muted,
    input  wire       I_song_enable,
    input  wire       I_lab_control_toggle,

    // Stable 50 MHz-domain narration-volume mailbox. Levels map to
    // 0/25/50/75/100 percent and are ramped in the audio domain.
    input  wire [2:0] I_voice_volume,
    input  wire       I_voice_volume_toggle,

    // Independent practice-page navigation event tokens.
    input  wire       I_practice_prev_tone_toggle,
    input  wire       I_practice_next_tone_toggle,
    input  wire       I_boot_success_tone_toggle,

    // 16 kHz signed 8-bit lesson narration from the TF/audio async FIFO.
    // Start/end are SD-domain toggles; FIFO data/flags are already in mclk.
    input  wire       I_voice_start_toggle,
    input  wire       I_voice_end_toggle,
    input  wire       I_voice_stop_toggle,
    input  wire [1:0] I_voice_clip_index,
    input  wire [7:0] I_voice_fifo_data,
    input  wire [1:0] I_voice_fifo_speed,
    input  wire       I_voice_fifo_valid,
    input  wire       I_voice_fifo_empty,
    input  wire       I_voice_played_to_end,
    output reg        O_voice_fifo_read,
    output wire       O_voice_sample_accept,
    output wire [1:0] O_voice_source_step,
    output reg        O_voice_subtitle_active,
    output reg [1:0]  O_voice_subtitle_clip,
    output reg [4:0]  O_voice_subtitle_cue,
    output reg        O_voice_subtitle_toggle,

    output reg        O_i2s_BCLK,
    output reg        O_i2s_LRCK,
    output reg        O_i2s_DOUT
);

localparam [5:0] FADE_FULL = 6'd32;
localparam [5:0] SONG_LAST_EVENT = 6'd63;
localparam integer SONG_GATE_FRAMES =
    (SONG_TICK_FRAMES > SONG_GAP_FRAMES) ?
    (SONG_TICK_FRAMES - SONG_GAP_FRAMES) : 1;

// The first sixteen teaching measures of Xiao Luo Hao, represented as scale
// degrees in F major. One tick is a sixteenth note at 100 BPM (7,200 samples
// at 48 kHz). The four regular phrases share one compact ROM.
function [3:0] song_note_lut;
    input [5:0] idx;
    begin
        case (idx[3:0])
            4'd0: song_note_lut = 4'd6;
            4'd1: song_note_lut = 4'd3;
            4'd2: song_note_lut = 4'd5;
            4'd3: song_note_lut = 4'd6;
            4'd4: song_note_lut = 4'd6;
            4'd5: song_note_lut = 4'd6;
            4'd6: song_note_lut = 4'd5;
            4'd7: song_note_lut = 4'd3;
            4'd8: song_note_lut = (idx[5:4] == 2'd2) ? 4'd6 : 4'd5;
            4'd9: song_note_lut = (idx[5:4] == 2'd2) ? 4'd5 : 4'd6;
            4'd10: song_note_lut = 4'd5;
            4'd11: song_note_lut = 4'd3;
            4'd12: song_note_lut = (idx[5:4] == 2'd2) ? 4'd5 : 4'd2;
            4'd13: song_note_lut = (idx[5:4] == 2'd2) ? 4'd6 : 4'd3;
            4'd14: begin
                case (idx[5:4])
                    2'd1: song_note_lut = 4'd5;
                    2'd2: song_note_lut = 4'd5;
                    default: song_note_lut = 4'd2;
                endcase
            end
            default: begin
                case (idx[5:4])
                    2'd0: song_note_lut = 4'd1;
                    2'd3: song_note_lut = 4'd1;
                    default: song_note_lut = 4'd3;
                endcase
            end
        endcase
    end
endfunction

function [3:0] song_duration_lut;
    input [5:0] idx;
    begin
        case (idx[3:0])
            4'd0: song_duration_lut = 4'd2;
            4'd1: song_duration_lut = 4'd1;
            4'd2: song_duration_lut = 4'd1;
            4'd3: song_duration_lut = 4'd2;
            4'd4: song_duration_lut = 4'd1;
            4'd5: song_duration_lut = 4'd1;
            4'd15: song_duration_lut = 4'd6;
            default: song_duration_lut = 4'd2;
        endcase
    end
endfunction

// F4..F5 DDS increments. The free-lab selector transposes the whole melody
// by one octave; quiz mode bypasses this table and keeps exact test tones.
function [31:0] song_note_inc;
    input [3:0] note;
    input [1:0] octave;
    reg [31:0] base_inc;
    begin
        case (note)
            4'd1: base_inc = 32'd31248413; // F4
            4'd2: base_inc = 32'd35075158; // G4
            4'd3: base_inc = 32'd39370534; // A4
            4'd4: base_inc = 32'd41711627; // Bb4
            4'd5: base_inc = 32'd46819719; // C5
            4'd6: base_inc = 32'd52553357; // D5
            4'd7: base_inc = 32'd58989149; // E5
            4'd8: base_inc = 32'd62496826; // F5
            default: base_inc = 32'd0;
        endcase

        case (octave)
            2'd0: song_note_inc = base_inc >> 1;
            2'd1: song_note_inc = base_inc;
            default: song_note_inc = base_inc << 1;
        endcase
    end
endfunction

// Exact phase increments for a 48 kHz sample stream, rounded to the nearest
// integer: 500 Hz, 1 kHz and 2 kHz.
function [31:0] lab_inc_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: lab_inc_lut = 32'd44739243;
            2'd1: lab_inc_lut = 32'd89478485;
            default: lab_inc_lut = 32'd178956971;
        endcase
    end
endfunction

// 32-entry signed sine lookup table, peak approximately 2,000,000.
function signed [23:0] sine_lut;
    input [4:0] idx;
    begin
        case (idx)
            5'd0:  sine_lut = 24'sd0;
            5'd1:  sine_lut = 24'sd390181;
            5'd2:  sine_lut = 24'sd765367;
            5'd3:  sine_lut = 24'sd1111140;
            5'd4:  sine_lut = 24'sd1414214;
            5'd5:  sine_lut = 24'sd1662939;
            5'd6:  sine_lut = 24'sd1847759;
            5'd7:  sine_lut = 24'sd1961571;
            5'd8:  sine_lut = 24'sd2000000;
            5'd9:  sine_lut = 24'sd1961571;
            5'd10: sine_lut = 24'sd1847759;
            5'd11: sine_lut = 24'sd1662939;
            5'd12: sine_lut = 24'sd1414214;
            5'd13: sine_lut = 24'sd1111140;
            5'd14: sine_lut = 24'sd765367;
            5'd15: sine_lut = 24'sd390181;
            5'd16: sine_lut = 24'sd0;
            5'd17: sine_lut = -24'sd390181;
            5'd18: sine_lut = -24'sd765367;
            5'd19: sine_lut = -24'sd1111140;
            5'd20: sine_lut = -24'sd1414214;
            5'd21: sine_lut = -24'sd1662939;
            5'd22: sine_lut = -24'sd1847759;
            5'd23: sine_lut = -24'sd1961571;
            5'd24: sine_lut = -24'sd2000000;
            5'd25: sine_lut = -24'sd1961571;
            5'd26: sine_lut = -24'sd1847759;
            5'd27: sine_lut = -24'sd1662939;
            5'd28: sine_lut = -24'sd1414214;
            5'd29: sine_lut = -24'sd1111140;
            5'd30: sine_lut = -24'sd765367;
            default: sine_lut = -24'sd390181;
        endcase
    end
endfunction

function signed [23:0] lab_wave_sample;
    input [31:0] phase;
    input [1:0] waveform;
    input [1:0] amplitude;
    input muted;
    reg [21:0] triangle_position;
    reg signed [23:0] full_sample;
    begin
        if (muted) begin
            lab_wave_sample = 24'sd0;
        end else begin
            case (waveform)
                2'd0: full_sample = phase[31] ? 24'sd2000000 :
                                                    -24'sd2000000;
                2'd1: begin
                    triangle_position = phase[31] ? ~phase[30:9] :
                                                       phase[30:9];
                    full_sample = $signed({1'b0, triangle_position}) -
                                  24'sd2097152;
                end
                default: full_sample = sine_lut(phase[31:27]);
            endcase

            case (amplitude)
                2'd0: lab_wave_sample = full_sample >>> 2;
                2'd1: lab_wave_sample = full_sample >>> 1;
                default: lab_wave_sample = full_sample;
            endcase
        end
    end
endfunction

function [5:0] voice_gain_lut;
    input [2:0] level;
    begin
        case (level)
            3'd0: voice_gain_lut = 6'd0;
            3'd1: voice_gain_lut = 6'd8;
            3'd2: voice_gain_lut = 6'd16;
            3'd3: voice_gain_lut = 6'd24;
            3'd4: voice_gain_lut = 6'd32;
            default: voice_gain_lut = 6'd0;
        endcase
    end
endfunction

reg [5:0] S_bit_cnt;
reg [63:0] S_shift_reg;
reg signed [23:0] S_sample_word;
reg S_audio_reset /* fehdl keep="true" */;

reg [31:0] S_lab_phase;
reg [5:0] S_song_event_idx;
reg [3:0] S_song_tick_count;
reg [15:0] S_song_tick_frame_count;

reg [2:0] S_control_toggle_sync /* fehdl keep="true" */;
reg S_control_toggle_seen;

// The mailbox payload is stable before the source toggles control_toggle.
// Two explicit capture stages keep every payload bit out of functional logic
// until it has settled; the three-stage toggle arrives one audio clock later.
reg       S_lab_active_meta /* fehdl keep="true" */;
reg       S_lab_active_sync /* fehdl keep="true" */;
reg [1:0] S_lab_frequency_meta /* fehdl keep="true" */;
reg [1:0] S_lab_frequency_sync /* fehdl keep="true" */;
reg [1:0] S_lab_amplitude_meta /* fehdl keep="true" */;
reg [1:0] S_lab_amplitude_sync /* fehdl keep="true" */;
reg [1:0] S_lab_waveform_meta /* fehdl keep="true" */;
reg [1:0] S_lab_waveform_sync /* fehdl keep="true" */;
reg       S_lab_muted_meta /* fehdl keep="true" */;
reg       S_lab_muted_sync /* fehdl keep="true" */;
reg       S_song_enable_meta /* fehdl keep="true" */;
reg       S_song_enable_sync /* fehdl keep="true" */;

reg [2:0] S_voice_start_toggle_sync /* fehdl keep="true" */;
reg [2:0] S_voice_end_toggle_sync /* fehdl keep="true" */;
reg [2:0] S_voice_volume_toggle_sync /* fehdl keep="true" */;
reg [2:0] S_practice_prev_tone_toggle_sync /* fehdl keep="true" */;
reg [2:0] S_practice_next_tone_toggle_sync /* fehdl keep="true" */;
reg       S_voice_start_toggle_seen;
reg       S_voice_end_toggle_seen;
reg       S_voice_volume_toggle_seen;
reg       S_practice_prev_tone_toggle_seen;
reg       S_practice_next_tone_toggle_seen;
reg [2:0] S_voice_volume_meta /* fehdl keep="true" */;
reg [2:0] S_voice_volume_sync /* fehdl keep="true" */;
reg [5:0] S_voice_volume_gain;
reg [5:0] S_voice_volume_target;
reg [1:0] S_voice_clip_meta /* fehdl keep="true" */;
reg [1:0] S_voice_clip_sync /* fehdl keep="true" */;
reg [1:0] S_voice_clip;
reg [2:0] S_voice_stop_sync /* fehdl keep="true" */;
reg S_voice_stop_seen;
reg [3:0] S_voice_token_warmup;
reg [5:0] S_voice_envelope;
reg [3:0] S_voice_fade_tick;
reg S_voice_fading, S_voice_discard;
reg S_voice_start_pending, S_voice_pending_end;
reg [1:0] S_voice_pending_clip;
reg       S_voice_active;
reg       S_voice_ending;
reg       S_voice_read_pending;
reg [4:0] S_voice_phase;
reg signed [23:0] S_voice_sample;
reg [19:0] S_voice_sample_count;
reg [1:0] S_voice_source_fraction;

function [2:0] voice_source_quarters;
    input [1:0] speed;
    begin
        case (speed)
            2'd0: voice_source_quarters = 3'd3;
            2'd1: voice_source_quarters = 3'd4;
            2'd2: voice_source_quarters = 3'd5;
            default: voice_source_quarters = 3'd4;
        endcase
    end
endfunction

function voice_is_v2;
    input [1:0] speed;
    begin
        case (speed)
            2'd0, 2'd1, 2'd2: voice_is_v2 = 1'b1;
            default: voice_is_v2 = 1'b0;
        endcase
    end
endfunction
reg       S_practice_tone_active;
reg       S_practice_tone_direction;
reg [31:0] S_practice_tone_phase;
reg [11:0] S_practice_tone_count;
reg [2:0] S_boot_tone_toggle_sync /* fehdl keep="true" */;
reg       S_boot_tone_toggle_seen;
reg       S_boot_tone_active;
reg [15:0] S_boot_tone_count;
reg [31:0] S_boot_tone_phase;

reg       S_lab_active;
reg [1:0] S_lab_frequency;
reg [1:0] S_lab_amplitude;
reg [1:0] S_lab_waveform;
reg       S_lab_muted;
reg       S_song_enable;

reg       S_pending_active;
reg [1:0] S_pending_frequency;
reg [1:0] S_pending_amplitude;
reg [1:0] S_pending_waveform;
reg       S_pending_muted;
reg       S_pending_song_enable;
reg       S_transition_pending;
reg       S_fade_up;
reg [5:0] S_gain;

wire [3:0] W_song_note = song_note_lut(S_song_event_idx);
wire [3:0] W_song_duration = song_duration_lut(S_song_event_idx);
wire W_song_gate = (W_song_note != 4'd0) &&
                   !((S_song_tick_count == W_song_duration - 4'd1) &&
                     (S_song_tick_frame_count >= SONG_GATE_FRAMES));
wire [31:0] W_lab_inc = S_song_enable ?
    song_note_inc(W_song_note, S_lab_frequency) :
    lab_inc_lut(S_lab_frequency);
wire signed [23:0] W_lab_sample =
    (S_song_enable && !W_song_gate) ? 24'sd0 :
    lab_wave_sample(S_lab_phase, S_lab_waveform,
                    S_lab_amplitude, S_lab_muted);
wire signed [30:0] W_voice_scaled_product =
    S_voice_sample * $signed({1'b0, S_voice_volume_gain});
wire signed [30:0] W_voice_scaled_sample =
    W_voice_scaled_product >>> 5;
wire [5:0] W_practice_tone_gain =
    (S_practice_tone_count < 12'd32) ?
        S_practice_tone_count[5:0] :
    (S_practice_tone_count >= (PRACTICE_TONE_SAMPLES - 32)) ?
        (PRACTICE_TONE_SAMPLES - 1 - S_practice_tone_count) : 6'd32;
wire [5:0] W_boot_tone_gain =
    (S_boot_tone_count < 16'd32) ? S_boot_tone_count[5:0] :
    (S_boot_tone_count >= BOOT_TONE_SAMPLES - 32) ?
        (BOOT_TONE_SAMPLES - 1 - S_boot_tone_count) : 6'd32;
wire [31:0] W_cue_tone_phase = S_practice_tone_active ?
    S_practice_tone_phase : S_boot_tone_phase;
wire [5:0] W_cue_tone_gain = S_practice_tone_active ?
    W_practice_tone_gain : W_boot_tone_gain;
wire signed [30:0] W_cue_tone_product =
    sine_lut(W_cue_tone_phase[31:27]) *
    $signed({1'b0, W_cue_tone_gain});
wire signed [23:0] W_practice_tone_sample =
    S_practice_tone_direction ?
        (W_cue_tone_product >>> 5) :
        (W_cue_tone_product >>> 4);
wire signed [23:0] W_boot_tone_sample = W_cue_tone_product >>> 5;
wire signed [23:0] W_selected_sample =
    S_voice_active ? W_voice_scaled_sample[23:0] :
    (S_practice_tone_active ? W_practice_tone_sample :
     (S_boot_tone_active ? W_boot_tone_sample :
      (S_lab_active ? W_lab_sample : 24'sd0)));
wire signed [30:0] W_scaled_product =
    W_selected_sample * $signed({1'b0,
        (S_voice_active ? S_voice_envelope : S_gain)});
wire signed [30:0] W_scaled_sample = W_scaled_product >>> 5;
wire signed [23:0] W_output_sample = W_scaled_sample[23:0];
wire W_control_update =
    S_control_toggle_sync[2] != S_control_toggle_seen;
wire W_voice_start_update =
    S_voice_token_warmup[3] &&
    S_voice_start_toggle_sync[2] != S_voice_start_toggle_seen;
assign O_voice_sample_accept = O_voice_fifo_read && I_voice_fifo_valid &&
    S_voice_active && !S_voice_discard && !S_voice_fading;
wire [3:0] W_voice_source_sum =
    {2'd0,S_voice_source_fraction} +
    {1'b0,voice_source_quarters(I_voice_fifo_speed)};
assign O_voice_source_step = voice_is_v2(I_voice_fifo_speed) ?
                             W_voice_source_sum[3:2] : 2'd1;
wire W_voice_stop_update = S_voice_token_warmup[3] &&
    S_voice_stop_sync[2] != S_voice_stop_seen;
wire W_voice_end_update =
    S_voice_token_warmup[3] &&
    S_voice_end_toggle_sync[2] != S_voice_end_toggle_seen;
wire W_voice_taper = S_voice_fading ||
    ((S_voice_ending ||
      (I_voice_played_to_end && S_voice_sample_count != 0)) &&
     I_voice_fifo_empty &&
     !S_voice_read_pending && S_voice_phase >= 5'd12);
wire W_voice_volume_update =
    S_voice_volume_toggle_sync[2] != S_voice_volume_toggle_seen;
// Every narration format consumes PCM at 16 kHz. LMV2 changes speed by
// selecting a pitch-preserved track in the SD domain; an older LMV1 card
// safely remains at 1x even when the UI speed setting changes.
wire [2:0] W_voice_speed_step = 3'd4;
wire W_practice_prev_tone_update =
    S_practice_prev_tone_toggle_sync[2] !=
    S_practice_prev_tone_toggle_seen;
wire W_practice_next_tone_update =
    S_practice_next_tone_toggle_sync[2] !=
    S_practice_next_tone_toggle_seen;
wire W_boot_tone_update =
    S_boot_tone_toggle_sync[2] != S_boot_tone_toggle_seen;
wire [4:0] W_voice_subtitle_cue;

lesson_subtitle_timing #(
    .SAMPLES_PER_TENTH(VOICE_SUBTITLE_SAMPLES_PER_TENTH)
) u_lesson_subtitle_timing (
    .clip_index  (S_voice_clip),
    .sample_count(S_voice_sample_count),
    .cue_index   (W_voice_subtitle_cue)
);

// Preserve one local reset stage so synthesis cannot fold the audio-domain
// reset release back into the 50 MHz stable_ready source. I_rst is already
// produced by clock_reset_manager's audio-domain release synchronizer.
always @(posedge I_mclk) begin
    S_audio_reset <= I_rst;
end

// Functional state observes only the local audio-domain reset register.
always @(posedge I_mclk) begin
    if (S_audio_reset) begin
        O_i2s_BCLK            <= 1'b0;
        O_i2s_LRCK            <= 1'b0;
        O_i2s_DOUT            <= 1'b0;
        S_bit_cnt             <= 6'd0;
        S_shift_reg           <= 64'd0;
        S_sample_word         <= 24'sd0;
        S_lab_phase           <= 32'd0;
        S_song_event_idx      <= 6'd0;
        S_song_tick_count     <= 4'd0;
        S_song_tick_frame_count <= 16'd0;
        S_control_toggle_sync <= 3'd0;
        S_control_toggle_seen <= 1'b0;
        S_lab_active_meta     <= 1'b0;
        S_lab_active_sync     <= 1'b0;
        S_lab_frequency_meta  <= 2'd0;
        S_lab_frequency_sync  <= 2'd0;
        S_lab_amplitude_meta  <= 2'd1;
        S_lab_amplitude_sync  <= 2'd1;
        S_lab_waveform_meta   <= 2'd0;
        S_lab_waveform_sync   <= 2'd0;
        S_lab_muted_meta      <= 1'b0;
        S_lab_muted_sync      <= 1'b0;
        S_song_enable_meta    <= 1'b0;
        S_song_enable_sync    <= 1'b0;
        S_voice_start_toggle_sync <= 3'd0;
        S_voice_end_toggle_sync <= 3'd0;
        S_voice_volume_toggle_sync <= 3'd0;
        S_practice_prev_tone_toggle_sync <= 3'd0;
        S_practice_next_tone_toggle_sync <= 3'd0;
        S_voice_start_toggle_seen <= 1'b0;
        S_voice_end_toggle_seen <= 1'b0;
        S_voice_volume_toggle_seen <= 1'b0;
        S_practice_prev_tone_toggle_seen <= 1'b0;
        S_practice_next_tone_toggle_seen <= 1'b0;
        S_voice_volume_meta     <= 3'd4;
        S_voice_volume_sync     <= 3'd4;
        S_voice_volume_gain     <= 6'd32;
        S_voice_volume_target   <= 6'd32;
        S_voice_clip_meta     <= 2'd0;
        S_voice_clip_sync     <= 2'd0;
        S_voice_clip          <= 2'd0;
        S_voice_stop_sync <= 0; S_voice_stop_seen <= 0;
        S_voice_token_warmup <= 0;
        S_voice_envelope <= 0; S_voice_fade_tick <= 0;
        S_voice_fading <= 0; S_voice_discard <= 0;
        S_voice_start_pending <= 0; S_voice_pending_end <= 0;
        S_voice_pending_clip <= 0;
        S_voice_active        <= 1'b0;
        S_voice_ending        <= 1'b0;
        S_voice_read_pending  <= 1'b0;
        S_voice_phase <= 5'd12;
        S_voice_sample        <= 24'sd0;
        S_voice_sample_count  <= 20'd0;
        S_voice_source_fraction <= 2'd0;
        S_practice_tone_active <= 1'b0;
        S_practice_tone_direction <= 1'b0;
        S_practice_tone_phase <= 32'd0;
        S_practice_tone_count <= 12'd0;
        S_boot_tone_toggle_sync <= 3'd0;
        S_boot_tone_toggle_seen <= 1'b0;
        S_boot_tone_active <= 1'b0;
        S_boot_tone_count <= 16'd0;
        S_boot_tone_phase <= 32'd0;
        O_voice_fifo_read     <= 1'b0;
        O_voice_subtitle_active <= 1'b0;
        O_voice_subtitle_clip <= 2'd0;
        O_voice_subtitle_cue  <= 5'd0;
        O_voice_subtitle_toggle <= 1'b0;
        S_lab_active          <= 1'b0;
        S_lab_frequency       <= 2'd0;
        S_lab_amplitude       <= 2'd1;
        S_lab_waveform        <= 2'd0;
        S_lab_muted           <= 1'b0;
        S_song_enable         <= 1'b0;
        S_pending_active      <= 1'b0;
        S_pending_frequency   <= 2'd0;
        S_pending_amplitude   <= 2'd1;
        S_pending_waveform    <= 2'd0;
        S_pending_muted       <= 1'b0;
        S_pending_song_enable <= 1'b0;
        S_transition_pending  <= 1'b0;
        S_fade_up             <= 1'b0;
        S_gain                <= FADE_FULL;
    end else begin
        S_control_toggle_sync <=
            {S_control_toggle_sync[1:0], I_lab_control_toggle};
        S_lab_active_meta    <= I_lab_active;
        S_lab_active_sync    <= S_lab_active_meta;
        S_lab_frequency_meta <= I_lab_frequency;
        S_lab_frequency_sync <= S_lab_frequency_meta;
        S_lab_amplitude_meta <= I_lab_amplitude;
        S_lab_amplitude_sync <= S_lab_amplitude_meta;
        S_lab_waveform_meta  <= I_lab_waveform;
        S_lab_waveform_sync  <= S_lab_waveform_meta;
        S_lab_muted_meta     <= I_lab_muted;
        S_lab_muted_sync     <= S_lab_muted_meta;
        S_song_enable_meta   <= I_song_enable;
        S_song_enable_sync   <= S_song_enable_meta;
        S_voice_start_toggle_sync <=
            {S_voice_start_toggle_sync[1:0], I_voice_start_toggle};
        S_voice_end_toggle_sync <=
            {S_voice_end_toggle_sync[1:0], I_voice_end_toggle};
        S_voice_volume_toggle_sync <=
            {S_voice_volume_toggle_sync[1:0], I_voice_volume_toggle};
        S_practice_prev_tone_toggle_sync <=
            {S_practice_prev_tone_toggle_sync[1:0],
             I_practice_prev_tone_toggle};
        S_practice_next_tone_toggle_sync <=
            {S_practice_next_tone_toggle_sync[1:0],
             I_practice_next_tone_toggle};
        S_boot_tone_toggle_sync <=
            {S_boot_tone_toggle_sync[1:0], I_boot_success_tone_toggle};
        S_voice_volume_meta <= I_voice_volume;
        S_voice_volume_sync <= S_voice_volume_meta;
        S_voice_clip_meta <= I_voice_clip_index;
        S_voice_clip_sync <= S_voice_clip_meta;
        S_voice_stop_sync <= {S_voice_stop_sync[1:0], I_voice_stop_toggle};
        S_voice_token_warmup <= {S_voice_token_warmup[2:0],1'b1};
        if (!S_voice_token_warmup[3]) begin
            S_voice_start_toggle_seen <= S_voice_start_toggle_sync[2];
            S_voice_end_toggle_seen <= S_voice_end_toggle_sync[2];
            S_voice_stop_seen <= S_voice_stop_sync[2];
        end
        O_voice_fifo_read <= 1'b0;
        // Discard a cancelled clip only after its audible envelope reaches
        // zero. New clips are produced only after the shared FIFO is empty.
        if (S_voice_discard && !S_voice_active && !S_voice_start_pending) begin
            if (I_voice_fifo_empty)
                S_voice_discard <= 1'b0;
            else
                O_voice_fifo_read <= 1'b1;
        end

        // Publish only cue changes derived from samples that have actually
        // reached the audio domain.  The stable payload plus toggle becomes a
        // frame-atomic mailbox in the video domain.
        if (S_voice_active &&
            (W_voice_subtitle_cue != O_voice_subtitle_cue)) begin
            O_voice_subtitle_cue <= W_voice_subtitle_cue;
            O_voice_subtitle_toggle <= ~O_voice_subtitle_toggle;
        end

        // Retry on the next stereo frame if a read lost validity at a reset
        // or empty boundary. Never leave the request permanently outstanding.
        if (O_voice_fifo_read)
            S_voice_read_pending <= 1'b0;
        if (O_voice_sample_accept) begin
            S_voice_sample <= $signed({I_voice_fifo_data, 16'd0});
            S_voice_read_pending <= 1'b0;
            if (voice_is_v2(I_voice_fifo_speed))
                S_voice_source_fraction <= W_voice_source_sum[1:0];
            if (S_voice_sample_count <= 20'hFFFFF - O_voice_source_step)
                S_voice_sample_count <= S_voice_sample_count + O_voice_source_step;
            else
                S_voice_sample_count <= 20'hFFFFF;
        end

        // Keep the established receiver-compatible 64fs serializer timing.
        O_i2s_BCLK <= ~O_i2s_BCLK;
        if (O_i2s_BCLK == 1'b1) begin
            O_i2s_DOUT  <= S_shift_reg[63];
            S_shift_reg <= {S_shift_reg[62:0], 1'b0};

            if (S_bit_cnt == 6'd63) begin
                S_bit_cnt <= 6'd0;
                if (O_i2s_LRCK == 1'b0) begin
                    O_i2s_LRCK  <= 1'b1;
                    S_shift_reg <= {S_sample_word[23:0], 40'd0};
                end else begin
                    O_i2s_LRCK    <= 1'b0;
                    S_sample_word <= W_output_sample;
                    S_shift_reg   <= {W_output_sample[23:0], 40'd0};

                    // Move one gain step per stereo frame. The longest
                    // transition is 24 frames (0.5 ms at 48 kHz), avoiding
                    // a discontinuity while remaining responsive.
                    if (S_voice_volume_gain < S_voice_volume_target)
                        S_voice_volume_gain <= S_voice_volume_gain + 6'd1;
                    else if (S_voice_volume_gain > S_voice_volume_target)
                        S_voice_volume_gain <= S_voice_volume_gain - 6'd1;

                    // Speech consumes one FIFO byte every three 48 kHz
                    // stereo frames. Tone/song time is frozen underneath the
                    // narration, and the melody is restarted when speech
                    // finishes so the learner always hears it from bar one.
                    if (S_voice_active) begin
                        if (W_voice_taper) begin
                            S_voice_fading <= 1'b1;
                            S_voice_fade_tick <= S_voice_fade_tick + 1'b1;
                            if (S_voice_envelope == 0) begin
                                S_voice_active <= 1'b0;
                                S_voice_ending <= 1'b0;
                                S_voice_sample <= 0;
                                S_voice_read_pending <= 0;
                                S_voice_phase <= 5'd12;
                                O_voice_subtitle_active <= 0;
                                O_voice_subtitle_toggle <= ~O_voice_subtitle_toggle;
                                S_lab_phase <= 0;
                                S_song_event_idx <= 0;
                                S_song_tick_count <= 0;
                                S_song_tick_frame_count <= 0;
                                S_gain <= 0;
                                S_fade_up <= 1'b1;
                            end else if (S_voice_fade_tick == 4'd15) begin
                                S_voice_envelope <= S_voice_envelope - 1'b1;
                            end
                        end else begin
                            S_voice_fade_tick <= S_voice_fade_tick + 1'b1;
                            if (S_voice_fade_tick == 4'd15 && S_voice_envelope < FADE_FULL)
                                S_voice_envelope <= S_voice_envelope + 1'b1;
                            if (S_voice_phase < 5'd12)
                                S_voice_phase <= S_voice_phase +
                                                 {2'd0,W_voice_speed_step};
                            else if (!S_voice_read_pending && !I_voice_fifo_empty) begin
                                O_voice_fifo_read <= 1'b1;
                                S_voice_read_pending <= 1'b1;
                                S_voice_phase <= S_voice_phase - 5'd12 +
                                                 {2'd0,W_voice_speed_step};
                            end
                        end
                    end else begin
                        if (S_practice_tone_active) begin
                            // Previous is a stronger 900 Hz cue for small HDMI
                            // speakers; next remains the proven 1.2 kHz cue.
                            // Both retain the 32-frame click taper.
                            S_practice_tone_phase <= S_practice_tone_phase +
                                (S_practice_tone_direction ?
                                 32'd107374182 : 32'd80530637);
                            if (S_practice_tone_count ==
                                PRACTICE_TONE_SAMPLES - 1) begin
                                S_practice_tone_active <= 1'b0;
                                S_practice_tone_phase <= 32'd0;
                                S_practice_tone_count <= 12'd0;
                            end else begin
                                S_practice_tone_count <=
                                    S_practice_tone_count + 12'd1;
                            end
                        end else if (S_boot_tone_active) begin
                            S_boot_tone_phase <= S_boot_tone_phase +
                                                 32'd89478485;
                            if (S_boot_tone_count == BOOT_TONE_SAMPLES - 1) begin
                                S_boot_tone_active <= 1'b0;
                                S_boot_tone_count <= 16'd0;
                                S_boot_tone_phase <= 32'd0;
                            end else begin
                                S_boot_tone_count <= S_boot_tone_count + 16'd1;
                            end
                        end else if (S_lab_active) begin
                            if (!S_song_enable || W_song_gate)
                                S_lab_phase <= S_lab_phase + W_lab_inc;
                            else
                                S_lab_phase <= 32'd0;

                            if (S_song_enable) begin
                                if (S_song_tick_frame_count ==
                                    SONG_TICK_FRAMES - 1) begin
                                    S_song_tick_frame_count <= 16'd0;
                                    if (S_song_tick_count ==
                                        W_song_duration - 4'd1) begin
                                        S_song_tick_count <= 4'd0;
                                        S_lab_phase <= 32'd0;
                                        if (S_song_event_idx == SONG_LAST_EVENT)
                                            S_song_event_idx <= 6'd0;
                                        else
                                            S_song_event_idx <=
                                                S_song_event_idx + 6'd1;
                                    end else begin
                                        S_song_tick_count <=
                                            S_song_tick_count + 4'd1;
                                    end
                                end else begin
                                    S_song_tick_frame_count <=
                                        S_song_tick_frame_count + 16'd1;
                                end
                            end
                        end
                    end

                    // A control change fades to zero, applies the complete
                    // pending mailbox atomically, then fades back to full.
                    if (S_voice_active && W_voice_taper && S_voice_envelope == 0) begin
                        S_gain <= 0;
                        S_fade_up <= 1;
                    end else if (S_transition_pending) begin
                        if (S_gain != 6'd0) begin
                            S_gain <= S_gain - 6'd1;
                        end else begin
                            S_lab_active     <= S_pending_active;
                            S_lab_frequency  <= S_pending_frequency;
                            S_lab_amplitude  <= S_pending_amplitude;
                            S_lab_waveform   <= S_pending_waveform;
                            S_lab_muted      <= S_pending_muted;
                            S_song_enable    <= S_pending_song_enable;
                            S_lab_phase      <= 32'd0;
                            S_song_event_idx <= 6'd0;
                            S_song_tick_count <= 4'd0;
                            S_song_tick_frame_count <= 16'd0;
                            S_transition_pending <= 1'b0;
                            S_fade_up        <= 1'b1;
                        end
                    end else if (S_fade_up) begin
                        if (S_gain == FADE_FULL)
                            S_fade_up <= 1'b0;
                        else
                            S_gain <= S_gain + 6'd1;
                    end
                end
            end else begin
                S_bit_cnt <= S_bit_cnt + 6'd1;
            end
        end

        // Mailbox arrival has priority over transition bookkeeping if it
        // happens on the same mclk as a stereo-frame boundary.
        if (W_control_update) begin
            S_control_toggle_seen <= S_control_toggle_sync[2];
            S_pending_active      <= S_lab_active_sync;
            S_pending_frequency   <= S_lab_frequency_sync;
            S_pending_amplitude   <= S_lab_amplitude_sync;
            S_pending_waveform    <= S_lab_waveform_sync;
            S_pending_muted       <= S_lab_muted_sync;
            S_pending_song_enable <= S_song_enable_sync;
            S_transition_pending  <= 1'b1;
            S_fade_up             <= 1'b0;
        end

        if (W_boot_tone_update) begin
            S_boot_tone_toggle_seen <= S_boot_tone_toggle_sync[2];
            if (!S_voice_active && !S_practice_tone_active &&
                !S_lab_active && !W_voice_start_update &&
                !W_practice_prev_tone_update &&
                !W_practice_next_tone_update) begin
                S_boot_tone_active <= 1'b1;
                S_boot_tone_count <= 16'd0;
                S_boot_tone_phase <= 32'd0;
            end
        end
        if (S_voice_active || S_practice_tone_active || S_lab_active ||
            W_voice_start_update || W_practice_prev_tone_update ||
            W_practice_next_tone_update ||
            (W_control_update && S_lab_active_sync)) begin
            S_boot_tone_active <= 1'b0;
            S_boot_tone_count <= 16'd0;
            S_boot_tone_phase <= 32'd0;
        end

        // Queue replacement until the old envelope is silent. A start and
        // end arriving together still describe a complete, possibly tiny clip.
        if (!S_voice_active && !S_voice_discard && S_voice_start_pending &&
            !W_voice_start_update && !W_voice_stop_update) begin
            S_voice_start_pending <= 0;
            S_voice_clip <= S_voice_pending_clip;
            S_voice_active <= 1;
            S_voice_ending <= S_voice_pending_end || W_voice_end_update;
            S_voice_fading <= 0;
            S_voice_envelope <= 0;
            S_voice_fade_tick <= 4'd15;
            S_voice_read_pending <= 0;
            S_voice_phase <= 5'd12;
            S_voice_sample <= 0;
            S_voice_sample_count <= 0;
            S_voice_source_fraction <= 0;
            O_voice_subtitle_active <= 1;
            O_voice_subtitle_clip <= S_voice_pending_clip;
            O_voice_subtitle_cue <= 0;
            O_voice_subtitle_toggle <= ~O_voice_subtitle_toggle;
        end
        if (W_voice_start_update && !W_voice_stop_update) begin
            S_voice_start_toggle_seen <= S_voice_start_toggle_sync[2];
            S_voice_start_pending <= 1;
            S_voice_pending_clip <= S_voice_clip_sync;
            S_voice_pending_end <= W_voice_end_update;
            S_voice_discard <= 0;
            if (S_voice_active) begin
                S_voice_fading <= 1;
                if (!S_voice_fading) S_voice_fade_tick <= 0;
            end
        end
        if (W_voice_end_update) begin
            S_voice_end_toggle_seen <= S_voice_end_toggle_sync[2];
            if (S_voice_start_pending || W_voice_start_update)
                S_voice_pending_end <= 1;
            else if (S_voice_active)
                S_voice_ending <= 1;
        end
        // Explicit page navigation starts the taper immediately and drops
        // remaining old PCM silently. Natural EOF continues consuming PCM.
        if (W_voice_stop_update) begin
            S_voice_stop_seen <= S_voice_stop_sync[2];
            S_voice_start_toggle_seen <= S_voice_start_toggle_sync[2];
            S_voice_start_pending <= 0;
            if (S_voice_active) begin
                S_voice_fading <= 1;
                if (!S_voice_fading) S_voice_fade_tick <= 0;
            end
            S_voice_discard <= 1;
        end

        if (W_voice_volume_update) begin
            S_voice_volume_toggle_seen <= S_voice_volume_toggle_sync[2];
            S_voice_volume_target <= voice_gain_lut(S_voice_volume_sync);
        end

        // A newer cue restarts the bounded envelope and replaces any older
        // pending cue. Narration still has sample-selection priority and
        // freezes this counter until speech is finished.
        if (W_practice_prev_tone_update) begin
            S_practice_prev_tone_toggle_seen <=
                S_practice_prev_tone_toggle_sync[2];
            S_practice_tone_direction <= 1'b0;
            S_practice_tone_active <= 1'b1;
            S_practice_tone_phase <= 32'd0;
            S_practice_tone_count <= 12'd0;
        end else if (W_practice_next_tone_update) begin
            S_practice_next_tone_toggle_seen <=
                S_practice_next_tone_toggle_sync[2];
            S_practice_tone_direction <= 1'b1;
            S_practice_tone_active <= 1'b1;
            S_practice_tone_phase <= 32'd0;
            S_practice_tone_count <= 12'd0;
        end
    end
end

endmodule
