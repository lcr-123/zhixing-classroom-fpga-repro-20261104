
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关
    input                       sw1,            // SETTINGS selector bit 0
    input                       sw2,
    input                       sw3,
    input                       sw4,
    input                       uart_rx,
    output                      uart_tx,
    // J1/JP1 pin 31=M15, pin 32=L16; external 3.3V pullups.
    inout                       light_scl,
    inout                       light_sda,

    output [7:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;
parameter BUF2_ADDR     = FRAME_PIXELS * 2;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;
wire effects_hs;
wire effects_vs;
wire effects_de;
wire audio_hs;
wire audio_vs;
wire audio_de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data_next;
wire [23:0] vout_data_blended;
wire [23:0] vout_data;
wire [23:0] vout_data_audio;
wire        eye_comfort_enable;
wire        eye_filter_enable;
wire        comfort_vs;
wire        comfort_de;
wire [23:0] comfort_rgb;
wire        display_valid;
wire        transition_active;
wire [4:0]  transition_alpha;
wire [1:0]  transition_effect;
wire        lesson_image_ready;

wire [3:0]  state_code;
wire [63:0] seg_status_segments;
// Keep the production image in normal status-display mode.  The isolated
// diagnostic build script changes this localparam in its copied workspace.
localparam SEG_DIAG_MODE = 1'b0;

// Learning-machine application state and metadata. The application core is
// clocked from the 50 MHz reference domain; only its page-change effect is
// later observed in the SD clock domain through the synchronized state gate.
localparam [3:0] APP_ST_BOOT_SELFTEST = 4'd0;
localparam [3:0] APP_ST_HOME          = 4'd1;
localparam [3:0] APP_ST_LEARN         = 4'd2;
localparam [3:0] APP_ST_QUIZ          = 4'd3;
localparam [3:0] APP_ST_FEEDBACK      = 4'd4;
localparam [3:0] APP_ST_WRONG_REVIEW  = 4'd5;
localparam [3:0] APP_ST_SOUND_LAB     = 4'd6;
localparam [3:0] APP_ST_SETTINGS      = 4'd7;
localparam [3:0] APP_ST_SUMMARY       = 4'd8;

wire [1:0]  learn_key_pressed;
wire [1:0]  learn_key_short;
wire [1:0]  learn_key_long;
wire [3:0]  learn_state;
wire [2:0]  learn_menu_index;
wire [2:0]  learn_page_index;
wire [3:0]  learn_image_index;
wire        practice_prefetch_valid_ref;
wire [3:0]  practice_prefetch_image_ref;
reg         prefetch_valid_mailbox_ref;
reg [3:0]   prefetch_image_mailbox_ref;
reg         prefetch_toggle_ref;
reg [1:0]   prefetch_ack_ref_sync;
reg [2:0]   prefetch_toggle_sd_sync;
reg [4:0]   prefetch_payload_sd_meta;
reg [4:0]   prefetch_payload_sd_sync;
reg [4:0]   prefetch_payload_sd;
reg         prefetch_ack_sd;
wire [3:0]  learn_page_number;
wire        learn_question_valid;
wire [2:0]  learn_question_type;
wire [7:0]  learn_prompt_token;
wire [7:0]  learn_option_a_token;
wire [7:0]  learn_option_b_token;
wire [7:0]  learn_option_c_token;
wire [7:0]  learn_option_d_token;
wire [1:0]  learn_expected_answer;
wire [1:0]  learn_difficulty;
wire        learn_music_quiz_audio_request;
wire        learn_answer_locked;
wire        learn_answer_correct;
wire        learn_quiz_complete;
wire [3:0]  learn_answered_count;
wire [3:0]  learn_correct_count;
wire [7:0]  learn_score_percent;
wire [1:0]  learn_star_level;
wire        learn_wrong_available;
wire [3:0]  learn_wrong_count;
wire [2:0]  learn_wrong_bitmap;
wire [2:0]  learn_first_wrong_question;
wire        learn_answer_in_review;
wire        learn_safe_recovery;
wire        sdr_init_done_ref;
wire        content_ready_sd;
reg         content_ready_ref_meta;
reg         content_ready_ref_sync;
wire        nav_next_event;
wire        lesson_auto_next_event;
wire        nav_prev_event;
wire        practice_double_click_active;
wire        learning_double_click_active;
wire        settings_zoom_navigation;
wire        practice_key2_single;
wire        practice_key2_double;
wire        key2_single_event;
wire        nav_select_event;
wire        nav_back_event;
wire        home_long_event;
wire        settings_decrement_event;
wire        settings_increment_event;
wire        lesson_volume_adjust_active;
wire [2:0]  lesson_volume_level;
wire        lesson_volume_control_toggle;
wire        lesson_speed_adjust_active;
wire [1:0]  lesson_speed_level;
wire        lesson_speed_toggle;
wire        sound_amplitude_event;
wire        sound_mute_event;
wire        sound_quiz_toggle_event;
wire        sound_quiz_advance_event;
wire        sound_quiz_submit_event;
wire        answer_valid_event;
wire        feedback_done_event;
wire        practice_prev_change_event;
wire        practice_next_change_event;
// Independent event tokens make previous/next cues directly observable in
// the audio domain without relying on a separately sampled direction payload.
reg         practice_prev_tone_toggle_ref;
reg         practice_next_tone_toggle_ref;
reg         boot_success_tone_toggle_ref;
reg         boot_success_tone_sent_ref;
// Keep answer selection inside the 50 MHz application domain. The adapter
// owns the retained key-choice register and synchronizes the four one-hot
// answer switches before either value reaches the application core.
wire [1:0]  learn_answer_choice;
wire        learn_answer_switch_active;
wire        learn_answer_selection_valid;
reg         sdr_init_sync1;
reg         sdr_init_sync2;
reg  [3:0]  learn_state_sd_sync1;
reg  [3:0]  learn_state_sd_sync2;
reg         home_request_toggle_ref;
reg         home_state_active_ref;
reg  [2:0]  home_request_toggle_sd_sync;
reg  [3:0]  app_image_mailbox_ref;
reg  [2:0]  app_image_zoom_mailbox_ref;
reg         app_image_prev_mailbox_ref;
reg         app_image_settings_mailbox_ref;
reg         app_image_request_toggle_ref;
reg         app_image_context_active_ref;
reg  [2:0]  app_image_request_toggle_sd_sync;
reg  [3:0]  app_image_index_sd_meta;
reg  [3:0]  app_image_index_sd_sync;
reg  [2:0]  app_image_zoom_sd_meta;
reg  [2:0]  app_image_zoom_sd_sync;
reg         app_image_prev_sd_meta;
reg         app_image_prev_sd_sync;
reg         app_image_settings_sd_meta;
reg         app_image_settings_sd_sync;
reg  [2:0]  zoom_request_toggle_sd_sync;
reg  [2:0]  zoom_level_sd_meta;
reg  [2:0]  zoom_level_sd_sync;
reg  [3:0]  zoom_image_index_sd_meta;
reg  [3:0]  zoom_image_index_sd_sync;
reg  [3:0]  osd_state_mailbox_ref;
reg  [2:0]  osd_wrong_mailbox_ref;
reg  [3:0]  osd_target_image_mailbox_ref;
reg         osd_state_toggle_ref;
wire        osd_state_ack_toggle;
reg [1:0]   osd_state_ack_ref_sync /* fehdl keep="true" */;
reg  [3:0]  learn_state_video_meta /* fehdl keep="true" */;
reg  [3:0]  learn_state_video_sync /* fehdl keep="true" */;
wire        sd_key_next;
wire        sd_key_auto;
wire        sd_home_request;
wire        sd_app_image_request;
wire        sd_zoom_request;
wire [3:0]  app_desired_image_index;
wire [2:0]  app_desired_zoom_level;
wire        app_image_context_active;
wire [2:0]  seg_question_index;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;
wire [31:0] video_read_data_b;
wire        video_frame_boundary;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx_sd;
wire [1:0]  disp_buf_idx;
wire [1:0]  transition_buf_idx;
wire [3:0]  display_image_idx_sd;
wire        display_page_right_sd;
wire        display_settings_entry_sd;
wire [3:0]  display_image_idx;
wire [2:0]  display_zoom_level_sd;
wire [2:0]  display_zoom_level;
wire        auto_play_active;
wire        display_valid_sd;
wire        display_commit_toggle;
wire        display_commit_ack_toggle;
wire [12:0] sd_debug_event_toggle;
wire        lesson_voice_fifo_write;
wire [9:0]  lesson_voice_fifo_write_data;
wire        lesson_voice_start_toggle;
wire        lesson_voice_end_toggle;
wire        lesson_voice_stop_toggle;
wire        lesson_voice_played_to_end;
wire        lesson_voice_sample_accept;
wire [1:0]  lesson_voice_source_step;
wire [1:0]  lesson_voice_clip_index;
wire [31:0] lesson_voice_sample_total;
wire [8:0] lesson_progress_video;
wire [1:0] lesson_progress_clip_video;
wire lesson_progress_valid_video;
wire        lesson_voice_fifo_read;
wire [9:0]  lesson_voice_fifo_read_data;
wire        lesson_voice_fifo_read_valid;
wire        lesson_voice_fifo_full;
wire        lesson_voice_fifo_empty;
wire [9:0]  lesson_voice_fifo_wrusedw;
wire [9:0]  lesson_voice_fifo_rdusedw;
wire        lesson_voice_fifo_space_available;
wire        lesson_voice_fifo_empty_write;
wire        lesson_voice_fifo_reset;
wire        lesson_voice_subtitle_active;
wire [1:0]  lesson_voice_subtitle_clip;
wire [4:0]  lesson_voice_subtitle_cue;
wire        lesson_voice_subtitle_toggle;
wire signed [2:0] uart_video_brightness;
wire        [1:0] uart_video_contrast;
wire              uart_video_osd_enable;
wire              uart_video_subtitle_enable;
wire              uart_video_control_toggle;
wire signed [2:0] video_brightness;
wire        [1:0] video_contrast;
wire              video_osd_enable;
wire              video_subtitle_enable;
wire              video_control_toggle;
wire        [2:0] video_zoom_level;
wire        [1:0] video_zoom_image_index;
wire              video_zoom_request_toggle;
wire        [1:0] settings_edit_parameter;
wire [15:0] ambient_raw, ambient_filtered, ambient_errors;
wire ambient_sample, ambient_sensor_valid, ambient_valid;
wire ambient_watchdog_tick;
wire signed [2:0] ambient_level;
wire auto_brightness_enable;
reg ambient_ready_ref;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;
wire        sys_pll_lock;
wire        video_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        sound_lab_active;
wire [1:0]  sound_lab_frequency;
wire [1:0]  sound_lab_amplitude;
wire [1:0]  sound_lab_waveform;
wire        sound_lab_muted;
wire        sound_lab_control_toggle;
wire        sound_lab_song_enable;
wire        sound_music_active_request;
wire        sound_quiz_active;
wire        sound_quiz_feedback;
wire        sound_quiz_complete;
wire        sound_quiz_answering;
wire [1:0]  sound_quiz_question;
wire [1:0]  sound_quiz_selected_answer;
wire [1:0]  sound_quiz_expected_answer;
wire        sound_quiz_answer_correct;
wire [3:0]  sound_quiz_answered_count;
wire [3:0]  sound_quiz_correct_count;
wire [7:0]  sound_quiz_score_percent;
wire [1:0]  sound_quiz_star_level;
wire [1:0]  sound_quiz_frequency;
wire [1:0]  sound_quiz_amplitude;
wire [1:0]  sound_quiz_waveform;
wire        sound_quiz_muted;
wire        sound_audio_quiz_active;
wire [1:0]  sound_audio_quiz_frequency;
wire [1:0]  sound_audio_quiz_amplitude;
wire [1:0]  sound_audio_quiz_waveform;
wire        sound_audio_quiz_muted;
wire        sound_audio_quiz_song_enable;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        thumbnail_request_toggle;
wire        thumbnail_done_toggle;
wire [15:0] thumbnail_frame_id;
wire [31:0] thumbnail_crc32;
wire [12:0] thumbnail_read_addr;
wire [15:0] thumbnail_read_data;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

wire rst_ref;
wire rst_sd;
wire rst_mem;
wire rst_video;
wire rst_hdmi_5x;
wire rst_audio;

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .extlock    (sys_pll_lock),
    .reset      (~rst_n)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .extlock    (video_pll_lock),
    .reset      (~rst_n)
);

// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (~rst_n),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

clock_reset_manager u_clock_reset_manager (
    .ref_clk        (clk),
    .ext_rst_n      (rst_n),
    .sys_pll_lock   (sys_pll_lock),
    .video_pll_lock (video_pll_lock),
    .audio_pll_lock (audio_pll_lock),
    .sd_clk         (sd_card_clk),
    .mem_clk        (ext_mem_clk),
    .video_clk      (video_clk),
    .hdmi_5x_clk    (hdmi_5x_clk),
    .audio_clk      (audio_mclk),
    .ref_rst        (rst_ref),
    .sd_rst         (rst_sd),
    .mem_rst        (rst_mem),
    .video_rst      (rst_video),
    .hdmi_5x_rst    (rst_hdmi_5x),
    .audio_rst      (rst_audio)
);

// Sdr_init_done is generated outside the 50 MHz reference domain. Synchronize
// its level before using it as the learning-core boot condition.
always @(posedge clk or posedge rst_ref) begin
    if (rst_ref) begin
        sdr_init_sync1 <= 1'b0;
        sdr_init_sync2 <= 1'b0;
    end else begin
        sdr_init_sync1 <= Sdr_init_done;
        sdr_init_sync2 <= sdr_init_sync1;
    end
end
assign sdr_init_done_ref = sdr_init_sync2;

// Existing board keys are active-low. The application layer emits debounced
// release events, while the legacy SD loader receives gated raw levels below.
learning_keypad #(
    .KEY_COUNT        (2),
    .COUNTER_WIDTH    (27),
    .DEBOUNCE_CYCLES  (1_000_000),
    // 0.5 s at 50 MHz.  The previous one-second mixed-width terminal count
    // passed reduced-parameter simulation but did not trigger on the board.
    .LONG_PRESS_CYCLES(25_000_000),
    .NAV_LONG_PRESS_CYCLES(17_500_000)
) u_learning_keypad (
    .clk              (clk),
    .rst              (rst_ref),
    .key_n_async      ({key2, key1}),
    .nav_long_mode    ({1'b0,
                        settings_zoom_navigation || practice_double_click_active}),
    .pressed          (learn_key_pressed),
    .short_press_pulse(learn_key_short),
    .long_press_pulse (learn_key_long)
);

assign practice_double_click_active = (learn_state == APP_ST_QUIZ) ||
                                      ((learn_state == APP_ST_FEEDBACK) &&
                                       !learn_answer_in_review) ||
                                      (learn_state == APP_ST_SUMMARY);
assign settings_zoom_navigation = (learn_state == APP_ST_SETTINGS) &&
                                  (settings_edit_parameter == 2'b10);
// Defer a learning navigation click until it can be distinguished from
// PREVIOUS. Parameter adjustments retain their immediate single-click path.
assign learning_double_click_active = (learn_state == APP_ST_LEARN) &&
                                      !lesson_volume_adjust_active &&
                                      !lesson_speed_adjust_active;
assign key2_single_event = (practice_double_click_active ||
                            learning_double_click_active ||
                            settings_zoom_navigation) ?
                           practice_key2_single : learn_key_short[0];

learning_key_double_click u_learning_key_double_click (
    .clk          (clk),
    .rst          (rst_ref),
    .active       (practice_double_click_active || learning_double_click_active ||
                   settings_zoom_navigation),
    .context_id   (learn_state),
    .short_pulse  (learn_key_short[0]),
    .long_pulse   (learn_key_long[0]),
    .single_pulse (practice_key2_single),
    .double_pulse (practice_key2_double)
);

learning_answer_input u_learning_answer_input (
    .clk                    (clk),
    .rst                    (rst_ref),
    .answer_page_active     ((learn_state == APP_ST_QUIZ) ||
                             (learn_state == APP_ST_WRONG_REVIEW) ||
                             sound_quiz_answering),
    .cycle_pulse            (key2_single_event),
    .switch_async           ({sw4, sw3, sw2, sw1}),
    .selected_answer        (learn_answer_choice),
    .switch_selection_active(learn_answer_switch_active),
    .selection_valid        (learn_answer_selection_valid)
);

// SW4 adjusts narration volume. SW3 adjusts narration speed when SW4 is down.
// Both modifiers leave the original navigation keys intact when lowered.
lesson_volume_control u_lesson_volume_control (
    .clk                (clk),
    .rst                (rst_ref),
    .learning_active    (learn_state == APP_ST_LEARN),
    .adjust_switch_async(sw4),
    .speed_switch_async (sw3),
    .decrement_pulse    (key2_single_event),
    .increment_pulse    (learn_key_short[1]),
    .adjust_mode_active (lesson_volume_adjust_active),
    .speed_adjust_active(lesson_speed_adjust_active),
    .volume_level       (lesson_volume_level),
    .control_toggle     (lesson_volume_control_toggle),
    .speed_level        (lesson_speed_level),
    .speed_toggle       (lesson_speed_toggle)
);

// Follow the actual audio-domain narration lifetime rather than SD prefetch.
// Pages 01 and 02 advance after their spoken lesson drains; page 03 stays
// visible until KEY4 starts the exercise. A manual page change invalidates
// the old completion tag, so it cannot skip a second page.
lesson_auto_advance u_lesson_auto_advance (
    .clk               (clk),
    .rst               (rst_ref),
    .app_state         (learn_state),
    .page_index        (learn_page_index),
    .voice_active_async(lesson_voice_subtitle_active),
    .voice_complete_async(lesson_voice_played_to_end),
    .auto_next_pulse   (lesson_auto_next_event)
);

assign nav_next_event = key2_single_event &&
                        ((learn_state == APP_ST_HOME) ||
                         ((learn_state == APP_ST_LEARN) &&
                          !lesson_volume_adjust_active &&
                          !lesson_speed_adjust_active));
assign nav_select_event = learn_key_short[1] &&
                          ((learn_state == APP_ST_HOME) ||
                           ((learn_state == APP_ST_LEARN) &&
                            !lesson_volume_adjust_active &&
                            !lesson_speed_adjust_active) ||
                           (learn_state == APP_ST_SUMMARY));
// Learning and practice defer the first release so a double click emits
// PREVIOUS without first advancing a lesson, cycling an answer or confirming.
assign nav_prev_event = (learn_key_long[0] &&
                         (((learn_state == APP_ST_LEARN) &&
                           !lesson_speed_adjust_active) ||
                          practice_double_click_active)) ||
                        ((practice_double_click_active || learning_double_click_active) &&
                         practice_key2_double);
assign nav_back_event = 1'b0;
// KEY4 long returns HOME in every application mode. KEY2 long and double
// request previous in practice; in SETTINGS zoom, long KEY2 selects next.
assign home_long_event = learn_key_long[1] |
                         (learn_key_long[0] &&
                          !nav_prev_event &&
                          !lesson_speed_adjust_active &&
                          (learn_state != APP_ST_QUIZ) &&
                          (learn_state != APP_ST_FEEDBACK) &&
                          (learn_state != APP_ST_SUMMARY) &&
                          (learn_state != APP_ST_SETTINGS) &&
                          (learn_state != APP_ST_SOUND_LAB));
assign settings_decrement_event = key2_single_event &&
                                  (learn_state == APP_ST_SETTINGS);
assign settings_increment_event = learn_key_short[1] &&
                                   (learn_state == APP_ST_SETTINGS);
assign sound_amplitude_event = key2_single_event &&
                               (((learn_state == APP_ST_LEARN) &&
                                 (learn_page_index == 3'd3)) ||
                                (learn_state == APP_ST_SOUND_LAB)) &&
                               !sound_quiz_active;
assign sound_mute_event = learn_key_short[1] &&
                          (learn_state == APP_ST_SOUND_LAB) &&
                          !sound_quiz_active;
assign sound_quiz_toggle_event = learn_key_long[0] &&
                                 (learn_state == APP_ST_SOUND_LAB);
assign sound_quiz_advance_event = key2_single_event &&
                                  (learn_state == APP_ST_SOUND_LAB) &&
                                  sound_quiz_active &&
                                  (sound_quiz_feedback ||
                                   sound_quiz_complete);
assign sound_quiz_submit_event = learn_key_short[1] &&
                                 (learn_state == APP_ST_SOUND_LAB) &&
                                 sound_quiz_answering &&
                                 learn_answer_selection_valid &&
                                 (learn_answer_choice != 2'd3);
assign sound_quiz_answering = sound_quiz_active &&
                              !sound_quiz_feedback &&
                              !sound_quiz_complete;
assign answer_valid_event = learn_key_short[1] &&
                            ((learn_state == APP_ST_QUIZ) ||
                             (learn_state == APP_ST_WRONG_REVIEW)) &&
                            learn_answer_selection_valid;
// KEY1 acknowledges feedback and also advances the legacy BMP loader, keeping
// the displayed card and the quiz cursor on the same step.
assign feedback_done_event = key2_single_event &&
                              (learn_state == APP_ST_FEEDBACK);

// The controller emits these pulses only when a practice page really moves.
// Use one token per direction. A real page move flips exactly one token, and
// boundary presses have already been removed by the controller.
always @(posedge clk or posedge rst_ref) begin
    if (rst_ref) begin
        practice_prev_tone_toggle_ref <= 1'b0;
        practice_next_tone_toggle_ref <= 1'b0;
    end else if (practice_prev_change_event) begin
        practice_prev_tone_toggle_ref <= ~practice_prev_tone_toggle_ref;
    end else if (practice_next_change_event) begin
        practice_next_tone_toggle_ref <= ~practice_next_tone_toggle_ref;
    end
end

// The first successful self-test exit is the only startup sound event.
always @(posedge clk or posedge rst_ref) begin
    if (rst_ref) begin
        boot_success_tone_toggle_ref <= 1'b0;
        boot_success_tone_sent_ref <= 1'b0;
    end else if (!boot_success_tone_sent_ref &&
                 (learn_state == APP_ST_HOME) && content_ready_ref_sync) begin
        boot_success_tone_toggle_ref <= ~boot_success_tone_toggle_ref;
        boot_success_tone_sent_ref <= 1'b1;
    end
end

// Carry every accepted HOME entry into the 100 MHz SD domain as a toggle,
// including automatic review completion. Queue it through the existing loader.
always @(posedge clk or posedge rst_ref) begin
    if (rst_ref) begin
        home_request_toggle_ref <= 1'b0;
        home_state_active_ref <= 1'b0;
    end else begin
        home_state_active_ref <= (learn_state == APP_ST_HOME);
        if ((learn_state == APP_ST_HOME) && !home_state_active_ref)
            home_request_toggle_ref <= ~home_request_toggle_ref;
    end
end

// Exact image routing for the eight-card course. Learning uses slots 0..3;
// the application core maps quiz/feedback/review to slots 4..7.  The former
// sound-lab state remains a bounded legacy fallback, but its home-menu entry
// now opens learning page 04 directly so adjustment and teaching are unified.
// Exercise pages become requestable only after the current session's random
// selection and metadata agree.  On entry to QUIZ the controller changes
// state one cycle before the selector latches its three cards; without this
// gate the default/previous first card is requested and then immediately
// replaced, which appears as two page turns.
assign app_image_context_active = (learn_state == APP_ST_LEARN) ||
                                  (learn_state == APP_ST_SETTINGS) ||
                                  (((learn_state == APP_ST_QUIZ) ||
                                    (learn_state == APP_ST_FEEDBACK) ||
                                    (learn_state == APP_ST_WRONG_REVIEW)) &&
                                   learn_question_valid) ||
                                  (learn_state == APP_ST_SOUND_LAB);
assign app_desired_image_index = (learn_state == APP_ST_SOUND_LAB) ?
                                 (sound_quiz_active ? 4'd7 : 4'd3) :
                                 (learn_state == APP_ST_SETTINGS) ? 4'd0 :
                                 learn_image_index;

always @(posedge clk or posedge rst_ref) begin
    if (rst_ref) begin
        app_image_mailbox_ref       <= 4'd0;
        app_image_zoom_mailbox_ref  <= 3'd2;
        app_image_prev_mailbox_ref  <= 1'b0;
        app_image_settings_mailbox_ref <= 1'b0;
        app_image_request_toggle_ref <= 1'b0;
        app_image_context_active_ref <= 1'b0;
    end else if (app_image_context_active) begin
        if (!app_image_context_active_ref ||
            (app_desired_image_index != app_image_mailbox_ref)) begin
            app_image_mailbox_ref        <= app_desired_image_index;
            app_image_zoom_mailbox_ref   <= app_desired_zoom_level;
            app_image_prev_mailbox_ref   <= practice_prev_change_event;
            app_image_settings_mailbox_ref <= (learn_state == APP_ST_SETTINGS);
            app_image_request_toggle_ref <= ~app_image_request_toggle_ref;
        end
        app_image_context_active_ref <= 1'b1;
    end else begin
        // Force a fresh exact-page request when the learner later re-enters a
        // course mode, even if HOME has meanwhile reloaded image zero.
        app_image_context_active_ref <= 1'b0;
    end
end

learning_app_core u_learning_app_core (
    .clk                    (clk),
    .rst                    (rst_ref),
    .boot_done              (content_ready_ref_sync),
    .content_ready          (content_ready_ref_sync),
    .nav_next_pulse         (nav_next_event | lesson_auto_next_event),
    .nav_prev_pulse         (nav_prev_event),
    .nav_select_pulse       (nav_select_event),
    .nav_back_pulse         (nav_back_event),
    .home_long_pulse        (home_long_event),
    .answer_valid           (answer_valid_event),
    .answer_code            (learn_answer_choice),
    .feedback_ack_pressed   (learn_key_pressed[0]),
    .feedback_done          (feedback_done_event),
    .state                  (learn_state),
    .menu_index             (learn_menu_index),
    .page_index             (learn_page_index),
    .image_index            (learn_image_index),
    .page_number            (learn_page_number),
    .question_valid         (learn_question_valid),
    .question_type          (learn_question_type),
    .prompt_token           (learn_prompt_token),
    .option_a_token         (learn_option_a_token),
    .option_b_token         (learn_option_b_token),
    .option_c_token         (learn_option_c_token),
    .option_d_token         (learn_option_d_token),
    .expected_answer        (learn_expected_answer),
    .difficulty             (learn_difficulty),
    .music_quiz_audio_request(learn_music_quiz_audio_request),
    .answer_locked          (learn_answer_locked),
    .answer_correct         (learn_answer_correct),
    .quiz_complete          (learn_quiz_complete),
    .answered_count         (learn_answered_count),
    .correct_count          (learn_correct_count),
    .score_percent          (learn_score_percent),
    .star_level             (learn_star_level),
    .wrong_questions_available(learn_wrong_available),
    .wrong_count            (learn_wrong_count),
    .wrong_question_bitmap  (learn_wrong_bitmap),
    .first_wrong_question   (learn_first_wrong_question),
    .answer_in_review       (learn_answer_in_review),
    .safe_recovery_pulse    (learn_safe_recovery),
    .practice_prev_change_pulse(practice_prev_change_event),
    .practice_next_change_pulse(practice_next_change_event),
    .practice_prefetch_valid(practice_prefetch_valid_ref),
    .practice_prefetch_image(practice_prefetch_image_ref)
);

// Acknowledged mailbox: keep the complete prefetch enable/index bundle stable
// until captured. Busy changes coalesce; video/navigation keep their existing
// independent mailboxes and never wait for this background hint.
always @(posedge clk or posedge rst_ref) begin
    if (rst_ref) begin
        prefetch_valid_mailbox_ref <= 1'b0;
        prefetch_image_mailbox_ref <= 4'd0;
        prefetch_toggle_ref <= 1'b0;
        prefetch_ack_ref_sync <= 2'b00;
    end else begin
        prefetch_ack_ref_sync <= {prefetch_ack_ref_sync[0], prefetch_ack_sd};
        if ((prefetch_ack_ref_sync[1] == prefetch_toggle_ref) &&
            ((practice_prefetch_valid_ref != prefetch_valid_mailbox_ref) ||
             (practice_prefetch_image_ref != prefetch_image_mailbox_ref))) begin
            prefetch_valid_mailbox_ref <= practice_prefetch_valid_ref;
            prefetch_image_mailbox_ref <= practice_prefetch_image_ref;
            prefetch_toggle_ref <= ~prefetch_toggle_ref;
        end
    end
end
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        prefetch_toggle_sd_sync <= 3'b000;
        prefetch_payload_sd_meta <= 5'd0;
        prefetch_payload_sd_sync <= 5'd0;
        prefetch_payload_sd <= 5'd0;
        prefetch_ack_sd <= 1'b0;
    end else begin
        prefetch_toggle_sd_sync <= {prefetch_toggle_sd_sync[1:0], prefetch_toggle_ref};
        prefetch_payload_sd_meta <= {prefetch_valid_mailbox_ref, prefetch_image_mailbox_ref};
        prefetch_payload_sd_sync <= prefetch_payload_sd_meta;
        if (prefetch_toggle_sd_sync[2] != prefetch_ack_sd) begin
            prefetch_payload_sd <= prefetch_payload_sd_sync;
            prefetch_ack_sd <= prefetch_toggle_sd_sync[2];
        end
    end
end

// Publish the complete application state through a toggle mailbox. The state
// word remains stable until acknowledged by the video domain. Busy updates
// coalesce into the latest complete payload after ACK; no source toggle can
// cancel an unreceived event. Pixel-domain changes commit at a frame boundary.
always @(posedge clk or posedge rst_ref) begin
    if (rst_ref)
        osd_state_ack_ref_sync <= 2'b00;
    else
        osd_state_ack_ref_sync <= {osd_state_ack_ref_sync[0], osd_state_ack_toggle};
end

always @(posedge clk or posedge rst_ref) begin
    if (rst_ref) begin
        osd_state_mailbox_ref <= APP_ST_BOOT_SELFTEST;
        osd_wrong_mailbox_ref <= 3'd0;
        osd_target_image_mailbox_ref <= 4'd0;
        osd_state_toggle_ref <= 1'b0;
    end else if ((osd_state_ack_ref_sync[1] == osd_state_toggle_ref) &&
                ((learn_state != osd_state_mailbox_ref) ||
                 (app_desired_image_index != osd_target_image_mailbox_ref) ||
                 ((learn_state == APP_ST_SUMMARY) &&
                  (learn_wrong_bitmap != osd_wrong_mailbox_ref)))) begin
        osd_state_mailbox_ref <= learn_state;
        osd_wrong_mailbox_ref <= learn_wrong_bitmap;
        osd_target_image_mailbox_ref <= app_desired_image_index;
        osd_state_toggle_ref <= ~osd_state_toggle_ref;
    end
end

// Synchronize the application state before gating raw keys in sd_card_clk.
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        learn_state_sd_sync1 <= APP_ST_BOOT_SELFTEST;
        learn_state_sd_sync2 <= APP_ST_BOOT_SELFTEST;
        home_request_toggle_sd_sync <= 3'b000;
        app_image_request_toggle_sd_sync <= 3'b000;
        app_image_index_sd_meta <= 4'd0;
        app_image_index_sd_sync <= 4'd0;
        app_image_zoom_sd_meta <= 3'd2;
        app_image_zoom_sd_sync <= 3'd2;
        app_image_prev_sd_meta <= 1'b0;
        app_image_prev_sd_sync <= 1'b0;
        app_image_settings_sd_meta <= 1'b0;
        app_image_settings_sd_sync <= 1'b0;
        zoom_request_toggle_sd_sync <= 3'b000;
        zoom_level_sd_meta <= 3'd2;
        zoom_level_sd_sync <= 3'd2;
        zoom_image_index_sd_meta <= 4'd0;
        zoom_image_index_sd_sync <= 4'd0;
    end else begin
        learn_state_sd_sync1 <= learn_state;
        learn_state_sd_sync2 <= learn_state_sd_sync1;
        home_request_toggle_sd_sync <=
            {home_request_toggle_sd_sync[1:0], home_request_toggle_ref};
        app_image_request_toggle_sd_sync <=
            {app_image_request_toggle_sd_sync[1:0], app_image_request_toggle_ref};
        app_image_index_sd_meta <= app_image_mailbox_ref;
        app_image_index_sd_sync <= app_image_index_sd_meta;
        app_image_zoom_sd_meta <= app_image_zoom_mailbox_ref;
        app_image_zoom_sd_sync <= app_image_zoom_sd_meta;
        app_image_prev_sd_meta <= app_image_prev_mailbox_ref;
        app_image_prev_sd_sync <= app_image_prev_sd_meta;
        app_image_settings_sd_meta <= app_image_settings_mailbox_ref;
        app_image_settings_sd_sync <= app_image_settings_sd_meta;
        zoom_request_toggle_sd_sync <=
            {zoom_request_toggle_sd_sync[1:0], video_zoom_request_toggle};
        zoom_level_sd_meta <= video_zoom_level;
        zoom_level_sd_sync <= zoom_level_sd_meta;
        zoom_image_index_sd_meta <= {2'b00, video_zoom_image_index};
        zoom_image_index_sd_sync <= zoom_image_index_sd_meta;
    end
end

assign sd_key_next = 1'b1;
assign sd_key_auto = 1'b1;
assign sd_home_request = (home_request_toggle_sd_sync[2] ^
                          home_request_toggle_sd_sync[1]);
assign sd_app_image_request = (app_image_request_toggle_sd_sync[2] ^
                               app_image_request_toggle_sd_sync[1]) &&
                              ((learn_state_sd_sync2 == APP_ST_LEARN) ||
                               (learn_state_sd_sync2 == APP_ST_QUIZ) ||
                               (learn_state_sd_sync2 == APP_ST_FEEDBACK) ||
                               (learn_state_sd_sync2 == APP_ST_WRONG_REVIEW) ||
                               (learn_state_sd_sync2 == APP_ST_SETTINGS) ||
                               (learn_state_sd_sync2 == APP_ST_SOUND_LAB));
assign sd_zoom_request = zoom_request_toggle_sd_sync[2] ^
                         zoom_request_toggle_sd_sync[1];
assign seg_question_index = ((learn_state == APP_ST_SOUND_LAB) &&
                             sound_quiz_active) ?
                            {1'b0, sound_quiz_question} : learn_page_index;

// Read-only debug sideband. It samples status and never gates the main path.
debug_uart #(
    .CLK_FRE (50)
) debug_uart_m0 (
    .clk                  (clk),
    .rst_n                (~rst_ref),
    .state_code           (state_code),
    .app_state            (learn_state),
    .app_target_image     (app_desired_image_index),
    .sd_debug_event_toggle(sd_debug_event_toggle),
    .video_commit_toggle  (display_commit_ack_toggle),
    .display_valid        (display_valid),
    .sdram_init_done      (Sdr_init_done),
    .sdram_refresh_active (Sdr_init_ref_vld),
    .sdram_busy           (Sdr_busy),
    .audio_pll_lock       (audio_pll_lock),
    .audio_valid          (audio_valid),
    .axis_ready           (axis_s_ready),
    .write_buf_idx        (write_buf_idx),
    .disp_buf_idx         (disp_buf_idx),
    .video_brightness     (uart_video_brightness),
    .video_contrast       (uart_video_contrast),
    .video_osd_enable     (uart_video_osd_enable),
    .video_subtitle_enable(uart_video_subtitle_enable),
    .video_control_toggle (uart_video_control_toggle),
    .thumbnail_request_toggle(thumbnail_request_toggle),
    .thumbnail_done_toggle(thumbnail_done_toggle),
    .thumbnail_frame_id   (thumbnail_frame_id),
    .thumbnail_crc32      (thumbnail_crc32),
    .thumbnail_read_addr  (thumbnail_read_addr),
    .thumbnail_read_data  (thumbnail_read_data),
    .uart_rx_pin          (uart_rx),
    .uart_tx_pin          (uart_tx)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
// 新 12 卡测试介质的首图 LBA 尚未核验，不能沿用旧八卡比赛卡的
// LBA8232 假设。先从 LBA0 安全扫描；冻结最终介质后再绑定真实首图。
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (4'd12),
    .AUTO_PLAY_ENABLE  (1'b0),
    .PREFETCH_ENABLE   (1'b1)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_sd),
    .key_next          (sd_key_next),
    .key_auto          (sd_key_auto),
    .home_request      (sd_home_request),
    .image_request     (sd_app_image_request),
    .image_request_idx (app_image_index_sd_sync),
    .image_request_zoom(app_image_zoom_sd_sync),
    .image_request_prev(app_image_prev_sd_sync),
    .image_request_settings(app_image_settings_sd_sync),
    .prefetch_enable   (prefetch_payload_sd[4]),
    .prefetch_image_idx(prefetch_payload_sd[3:0]),
    .zoom_request      (sd_zoom_request),
    .zoom_level        (zoom_level_sd_sync),
    .zoom_image_idx    (zoom_image_index_sd_sync),
    .narration_enable  (learn_state_sd_sync2 == APP_ST_LEARN),
    .voice_speed_level(lesson_speed_level),
    .voice_speed_toggle(lesson_speed_toggle),
    .voice_fifo_space_available(lesson_voice_fifo_space_available),
    .voice_fifo_empty  (lesson_voice_fifo_empty_write),
    .content_ready     (content_ready_sd),
    .state_code        (state_code),
    .display_image_idx (display_image_idx_sd),
    .display_page_right(display_page_right_sd),
    .display_settings_entry(display_settings_entry_sd),
    .debug_event_toggle(sd_debug_event_toggle),
    .auto_play_active  (auto_play_active),
    .display_zoom_level(display_zoom_level_sd),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid_sd),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx_sd),
    .display_commit_toggle(display_commit_toggle),
    .display_commit_ack_toggle(display_commit_ack_toggle),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .voice_fifo_write  (lesson_voice_fifo_write),
    .voice_fifo_data   (lesson_voice_fifo_write_data),
    .voice_start_toggle(lesson_voice_start_toggle),
    .voice_end_toggle  (lesson_voice_end_toggle),
    .voice_stop_toggle (lesson_voice_stop_toggle),
    .voice_clip_index  (lesson_voice_clip_index),
    .voice_sample_total(lesson_voice_sample_total),
    .narration_busy    (),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

// One 1024-byte dual-clock FIFO absorbs complete TF sectors while the audio
// side consumes 16 kHz signed PCM.  The SD reader starts another 512-byte
// sector only after occupancy falls to 256 bytes or less, so the unthrottled
// SPI burst cannot overflow the FIFO.
// Feed the FIFO from one reset tree only.  The FIFO already performs its own
// asynchronous-assert/synchronous-release synchronization in both clock
// domains; OR-ing two independently released domain resets adds a long
// combinational reset path and unnecessary hold-fix pressure.
assign lesson_voice_fifo_reset = rst_ref;
assign lesson_voice_fifo_space_available =
    (lesson_voice_fifo_wrusedw <= 10'd256);
assign lesson_voice_fifo_empty_write =
    (lesson_voice_fifo_wrusedw == 10'd0);

always @(posedge clk or posedge rst_ref) begin
    if (rst_ref) begin
        content_ready_ref_meta <= 1'b0;
        content_ready_ref_sync <= 1'b0;
    end else begin
        content_ready_ref_meta <= content_ready_sd;
        content_ready_ref_sync <= content_ready_ref_meta;
    end
end

wfifo_32_32_512 #(
    .DATA_WIDTH_W (10),
    .DATA_WIDTH_R (10),
    .ADDR_WIDTH_W (10),
    .ADDR_WIDTH_R (10),
    .AL_FULL_NUM  (1000),
    .AL_EMPTY_NUM (2)
) u_lesson_voice_fifo (
    .rst        (lesson_voice_fifo_reset),
    .clkw       (sd_card_clk),
    .clkr       (audio_mclk),
    .we         (lesson_voice_fifo_write),
    .di         (lesson_voice_fifo_write_data),
    .re         (lesson_voice_fifo_read),
    .dout       (lesson_voice_fifo_read_data),
    .valid      (lesson_voice_fifo_read_valid),
    .full_flag  (lesson_voice_fifo_full),
    .empty_flag (lesson_voice_fifo_empty),
    .afull      (),
    .aempty     (),
    .wrusedw    (lesson_voice_fifo_wrusedw),
    .rdusedw    (lesson_voice_fifo_rdusedw)
);

learning_seg_status u_learning_seg_status (
    .app_state                 (learn_state),
    .question_index            (seg_question_index),
    .boot_state_code           (state_code),
    .settings_index            (settings_edit_parameter),
    .answer_selection_valid    (learn_answer_selection_valid),
    .answer_choice             (learn_answer_choice),
    .answer_correct            (learn_answer_correct),
    .sound_quiz_active         (sound_quiz_active),
    .sound_quiz_feedback       (sound_quiz_feedback),
    .sound_quiz_complete       (sound_quiz_complete),
    .sound_quiz_answer_correct (sound_quiz_answer_correct),
    .segments                  (seg_status_segments)
);

seg_scan #(
    .SEG_DIAG_MODE     (SEG_DIAG_MODE)
) seg_scan_m0(
    .clk               (clk),
    .rst_n             (~rst_ref),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        (seg_status_segments[7:0]),
    .seg_data_1        (seg_status_segments[15:8]),
    .seg_data_2        (seg_status_segments[23:16]),
    .seg_data_3        (seg_status_segments[31:24]),
    .seg_data_4        (seg_status_segments[39:32]),
    .seg_data_5        (seg_status_segments[47:40]),
    .seg_data_6        (seg_status_segments[55:48]),
    .seg_data_7        (seg_status_segments[63:56])
);

// SETTINGS selector {SW2,SW1}: 00 brightness, 01 contrast, 10 zoom and 11
// eye comfort. In zoom mode long KEY2 selects next and double KEY2 selects
// previous; each image owns an
// independent five-level zoom value. Requested values reach the OSD at once;
// rapid edits settle briefly and collapse into one complete BMP reread.
bh1750_reader u_bh1750_reader (
    .clk(clk), .rst(rst_ref), .scl(light_scl), .sda(light_sda),
    .sample_raw(ambient_raw), .sample_valid(ambient_sample),
    .watchdog_tick(ambient_watchdog_tick),
    .sensor_valid(ambient_sensor_valid), .error_count(ambient_errors)
);
ambient_brightness #(.STALE_CYCLES(300_000)) u_ambient_brightness (
    .clk(clk), .rst(rst_ref), .sample_raw(ambient_raw),
    .sample_valid(ambient_sample), .sensor_valid(ambient_sensor_valid),
    .watchdog_tick(ambient_watchdog_tick),
    .level(ambient_level), .valid(ambient_valid), .filtered_raw(ambient_filtered)
);
always @(posedge clk) begin
    if (rst_ref) ambient_ready_ref<=0;
    else ambient_ready_ref<=ambient_valid;
end
video_control_arbiter #(.ENABLE_AMBIENT(1)) u_video_control_arbiter (
    .clk                    (clk),
    .rst                    (rst_ref),
    .uart_brightness        (uart_video_brightness),
    .uart_contrast          (uart_video_contrast),
    .uart_osd_enable        (uart_video_osd_enable),
    .uart_subtitle_enable   (uart_video_subtitle_enable),
    .uart_control_toggle    (uart_video_control_toggle),
    .settings_active        (learn_state == APP_ST_SETTINGS),
    .select_parameter_async ({sw2, sw1}),
    .zoom_next_pulse        (settings_zoom_navigation && learn_key_long[0]),
    .zoom_prev_pulse        (settings_zoom_navigation && practice_key2_double),
    .decrement_pulse        (settings_decrement_event),
    .increment_pulse        (settings_increment_event),
    .auto_selector_async    (sw3),
    .ambient_level          (ambient_level),
    .ambient_valid          (ambient_valid),
    .auto_brightness_enable (auto_brightness_enable),
    .brightness             (video_brightness),
    .contrast               (video_contrast),
    .osd_enable             (video_osd_enable),
    .subtitle_enable        (video_subtitle_enable),
    .control_toggle         (video_control_toggle),
    .zoom_level             (video_zoom_level),
    .zoom_image_index       (video_zoom_image_index),
    .zoom_lookup_index      (app_desired_image_index[1:0]),
    .zoom_lookup_level      (app_desired_zoom_level),
    .zoom_request_toggle    (video_zoom_request_toggle),
    .editing_parameter      (settings_edit_parameter),
    .eye_comfort_enable     (eye_comfort_enable)
);

// A KEY2 long press enters/exits the three-question listening game.  Answer
// selection now follows the same visible convention as the four course
// exercises: SW1/SW2/SW3 directly select A/B/C, or with all switches down a
// short KEY2 press cycles A/B/C. KEY4 submits. The shared selector rejects
// ambiguous multi-switch states and SW4/D for this three-choice exercise.
// The game reuses quiz_engine scoring and overrides only the sound-lab
// controls; the free laboratory settings remain intact and return on exit.
sound_quiz_game u_sound_quiz_game (
    .clk                    (clk),
    .rst                    (rst_ref),
    .lab_active             (learn_state == APP_ST_SOUND_LAB),
    .toggle_game_pulse      (sound_quiz_toggle_event),
    .advance_pulse          (sound_quiz_advance_event),
    .submit_pulse           (sound_quiz_submit_event),
    .answer_code            (learn_answer_choice),
    .answer_valid           (learn_answer_selection_valid &&
                             (learn_answer_choice != 2'd3)),
    .game_active            (sound_quiz_active),
    .feedback_active        (sound_quiz_feedback),
    .game_complete          (sound_quiz_complete),
    .question_index         (sound_quiz_question),
    .selected_answer        (sound_quiz_selected_answer),
    .expected_answer        (sound_quiz_expected_answer),
    .answer_correct         (sound_quiz_answer_correct),
    .answered_count         (sound_quiz_answered_count),
    .correct_count          (sound_quiz_correct_count),
    .score_percent          (sound_quiz_score_percent),
    .star_level             (sound_quiz_star_level),
    .audio_frequency        (sound_quiz_frequency),
    .audio_amplitude        (sound_quiz_amplitude),
    .audio_waveform         (sound_quiz_waveform),
    .audio_muted            (sound_quiz_muted)
);

// SOUND_LAB free-mode plays the first-section teaching melody of Xiao Luo Hao.
// {SW2,SW1}=low/original/high octave, {SW4,SW3}=square/triangle/sine,
// KEY2 cycles amplitude and KEY4 toggles mute.  The listening quiz disables
// the sequencer and reuses the exact fixed test tones through the same mailbox.
// The fourth learning card starts the same melody automatically, completing
// the learn-before-practice path without adding another audio clock crossing.
// The page-08 exercise plays the Xiao Luo Hao teaching melody at a fixed high
// octave with a square waveform.  One visible choice therefore identifies
// pitch and waveform together. Dynamic legacy sound-lab questions retain
// fixed single tones, and answer switches cannot alter the sound under test.
assign sound_audio_quiz_active = sound_quiz_active;
assign sound_audio_quiz_frequency = sound_quiz_active ?
                                    sound_quiz_frequency : 2'd2;
assign sound_audio_quiz_amplitude = sound_quiz_active ?
                                    sound_quiz_amplitude : 2'd2;
assign sound_audio_quiz_waveform = sound_quiz_active ?
                                   sound_quiz_waveform : 2'd0;
assign sound_audio_quiz_muted = sound_quiz_active ?
                                sound_quiz_muted : 1'b0;
assign sound_audio_quiz_song_enable = 1'b0;
assign sound_music_active_request =
    (learn_state == APP_ST_SOUND_LAB);

sound_lab_control u_sound_lab_control (
    .clk                    (clk),
    .rst                    (rst_ref),
    .lab_active_request     (sound_music_active_request),
    .switch_async           ({sw4, sw3, sw2, sw1}),
    .amplitude_cycle_pulse  (sound_amplitude_event),
    .mute_toggle_pulse      (sound_mute_event),
    .quiz_active            (sound_audio_quiz_active),
    .quiz_frequency         (sound_audio_quiz_frequency),
    .quiz_amplitude         (sound_audio_quiz_amplitude),
    .quiz_waveform          (sound_audio_quiz_waveform),
    .quiz_muted             (sound_audio_quiz_muted),
    .quiz_song_enable       (sound_audio_quiz_song_enable),
    .lab_active             (sound_lab_active),
    .frequency_select       (sound_lab_frequency),
    .amplitude_level        (sound_lab_amplitude),
    .waveform_select        (sound_lab_waveform),
    .muted                  (sound_lab_muted),
    .song_enable            (sound_lab_song_enable),
    .control_toggle         (sound_lab_control_toggle)
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .frame_boundary    (video_frame_boundary)
);

frame_buffer_commit #(
    .TRANSITION_STEPS(8)
) u_frame_buffer_commit (
    .pixel_clk           (video_clk),
    .pixel_rst           (rst_video),
    .frame_boundary      (video_frame_boundary),
    .source_buf_idx      (disp_buf_idx_sd),
    .source_image_idx    (display_image_idx_sd),
    .source_page_right   (display_page_right_sd),
    .source_settings_entry(display_settings_entry_sd),
    .source_zoom_level   (display_zoom_level_sd),
    .source_display_valid(display_valid_sd),
    .source_commit_toggle(display_commit_toggle),
    .commit_ack_toggle   (display_commit_ack_toggle),
    .display_buf_idx     (disp_buf_idx),
    .transition_buf_idx  (transition_buf_idx),
    .display_image_idx   (display_image_idx),
    .display_zoom_level  (display_zoom_level),
    .display_valid       (display_valid),
    .lesson_image_ready  (lesson_image_ready),
    .transition_active   (transition_active),
    .transition_alpha    (transition_alpha),
    .transition_effect   (transition_effect)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .read_data_b       (video_read_data_b[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw),
    .vout_data_b       (vout_data_next)
);

video_transition_blend u_video_transition_blend (
    .pixel_clk          (video_clk),
    .pixel_rst          (rst_video),
    .frame_boundary     (video_frame_boundary),
    .in_de              (de),
    .current_rgb       (display_valid ? vout_data_raw : 24'd0),
    .next_rgb          (vout_data_next),
    .transition_active (transition_active),
    .transition_alpha  (transition_alpha),
    .transition_effect (transition_effect),
    .blended_rgb       (vout_data_blended)
);

video_effects_osd #(.ENABLE_AMBIENT_OSD(1)) u_video_effects_osd (
    .pixel_clk             (video_clk),
    .pixel_rst             (rst_video),
    .frame_boundary        (video_frame_boundary),
    .in_hs                 (hs),
    .in_vs                 (vs),
    .in_de                 (de),
    .in_rgb                (vout_data_blended),
    .source_brightness     (video_brightness),
    .source_contrast       (video_contrast),
    .source_osd_enable     (video_osd_enable),
    .source_subtitle_enable(video_subtitle_enable),
    .source_control_toggle (video_control_toggle),
    .source_ambient_enable (auto_brightness_enable),
    .source_ambient_ready  (ambient_ready_ref),
    .source_zoom_preview_level(video_zoom_level),
    .display_image_idx     (display_image_idx),
    .display_zoom_level    (display_zoom_level),
    .display_valid         (display_valid),
    .transition_active     (transition_active),
    .source_state_code     (osd_state_mailbox_ref),
    .source_wrong_bitmap   (osd_wrong_mailbox_ref),
    .source_target_image_idx(osd_target_image_mailbox_ref),
    .source_state_toggle   (osd_state_toggle_ref),
    .state_ack_toggle      (osd_state_ack_toggle),
    .source_auto_play      (auto_play_active),
    .source_volume_level   (lesson_volume_level),
    .source_volume_toggle  (lesson_volume_control_toggle),
    .source_speed_level    (lesson_speed_level),
    .source_speed_toggle   (lesson_speed_toggle),
    .voice_progress        (lesson_progress_video),
    .voice_clip            (lesson_progress_clip_video),
    .voice_valid           (lesson_progress_valid_video),
    .source_eye_comfort_enable(eye_comfort_enable),
    .eye_filter_enable     (eye_filter_enable),
    .source_lesson_subtitle_active(lesson_voice_subtitle_active),
    .source_lesson_subtitle_clip(lesson_voice_subtitle_clip),
    .source_lesson_subtitle_cue(lesson_voice_subtitle_cue),
    .source_lesson_subtitle_toggle(lesson_voice_subtitle_toggle),
    .out_hs                (effects_hs),
    .out_vs                (effects_vs),
    .out_de                (effects_de),
    .out_rgb               (vout_data)
);

// Show the real HDMI PCM waveform directly above the 16-pixel subtitle row.
// Waveform y=416..447; y=448..463 stays clear and the original lesson
// subtitle remains at y=464..479. Numeric audio status shares the top OSD row.
// Gate it from the synchronized application state so practice/feedback pages
// cannot inherit the previous lesson frame's audio visualization.
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        learn_state_video_meta <= APP_ST_BOOT_SELFTEST;
        learn_state_video_sync <= APP_ST_BOOT_SELFTEST;
    end else begin
        learn_state_video_meta <= learn_state;
        learn_state_video_sync <= learn_state_video_meta;
    end
end

lesson_audio_status u_lesson_audio_status (
    .audio_clk(audio_mclk), .audio_rst(rst_audio),
    .source_start_toggle(lesson_voice_start_toggle),
    .source_stop_toggle(lesson_voice_stop_toggle),
    .source_total(lesson_voice_sample_total),
    .source_clip(lesson_voice_clip_index),
    .consume(lesson_voice_sample_accept),
    .consume_step(lesson_voice_source_step),
    .played_to_end(lesson_voice_played_to_end),
    .pixel_clk(video_clk), .pixel_rst(rst_video),
    .frame_boundary(video_frame_boundary),
    .progress(lesson_progress_video), .clip(lesson_progress_clip_video),
    .valid(lesson_progress_valid_video)
);

audio_waveform_overlay #(
    .FRAME_WIDTH (640),
    .FRAME_HEIGHT(480),
    .WAVE_WIDTH  (640),
    .WAVE_TOP    (416),
    .WAVE_HEIGHT (32)
) u_audio_waveform_overlay (
    .pixel_clk      (video_clk),
    .pixel_rst      (rst_video),
    .frame_boundary (video_frame_boundary),
    .in_hs          (effects_hs),
    .in_vs          (effects_vs),
    .in_de          (effects_de),
    .in_rgb         (vout_data),
    .overlay_enable ((learn_state_video_sync == APP_ST_LEARN) &&
                     lesson_image_ready),
    .theme_index    (display_image_idx),
    .audio_valid    (audio_valid),
    .audio_sample   (audio_left_data),
    .out_hs         (audio_hs),
    .out_vs         (audio_vs),
    .out_de         (audio_de),
    .out_rgb        (vout_data_audio)
);

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (24'd0),
    .read_addr_index   (disp_buf_idx),
    .read_addr_index_b (transition_buf_idx),
    .read_dual         (transition_active),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),
    .read_data_b       (video_read_data_b),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== 音频：讲解 / 小螺号 / 声音实验室 =====================
hdmi_audio_tone_i2s_64fs #(
    .VOICE_SUBTITLE_SAMPLES_PER_TENTH(1600)
) u_hdmi_audio_tone_i2s_64fs (
    .I_mclk      (audio_mclk),
    .I_rst       (rst_audio),
    .I_lab_active(sound_lab_active),
    .I_lab_frequency(sound_lab_frequency),
    .I_lab_amplitude(sound_lab_amplitude),
    .I_lab_waveform(sound_lab_waveform),
    .I_lab_muted  (sound_lab_muted),
    .I_song_enable(sound_lab_song_enable),
    .I_lab_control_toggle(sound_lab_control_toggle),
    .I_voice_volume(lesson_volume_level),
    .I_voice_volume_toggle(lesson_volume_control_toggle),
    .I_practice_prev_tone_toggle(practice_prev_tone_toggle_ref),
    .I_practice_next_tone_toggle(practice_next_tone_toggle_ref),
    .I_boot_success_tone_toggle(boot_success_tone_toggle_ref),
    .I_voice_start_toggle(lesson_voice_start_toggle),
    .I_voice_end_toggle(lesson_voice_end_toggle),
    .I_voice_stop_toggle(lesson_voice_stop_toggle),
    .I_voice_clip_index(lesson_voice_clip_index),
    .I_voice_fifo_data(lesson_voice_fifo_read_data[7:0]),
    .I_voice_fifo_speed(lesson_voice_fifo_read_data[9:8]),
    .I_voice_fifo_valid(lesson_voice_fifo_read_valid),
    .I_voice_fifo_empty(lesson_voice_fifo_empty),
    .I_voice_played_to_end(lesson_voice_played_to_end),
    .O_voice_fifo_read(lesson_voice_fifo_read),
    .O_voice_sample_accept(lesson_voice_sample_accept),
    .O_voice_source_step(lesson_voice_source_step),
    .O_voice_subtitle_active(lesson_voice_subtitle_active),
    .O_voice_subtitle_clip(lesson_voice_subtitle_clip),
    .O_voice_subtitle_cue(lesson_voice_subtitle_cue),
    .O_voice_subtitle_toggle(lesson_voice_subtitle_toggle),
    .O_i2s_BCLK  (audio_i2s_bclk),
    .O_i2s_LRCK  (audio_i2s_lrck),
    .O_i2s_DOUT  (audio_i2s_dout)
);

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_video),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// Final color stage includes OSD, lesson subtitles and the PCM overlay.
video_eye_comfort u_video_eye_comfort (
    .pixel_clk(video_clk), .pixel_rst(rst_video),
    .enable(eye_filter_enable),
    .in_hs(audio_hs), .in_vs(audio_vs), .in_de(audio_de),
    .in_rgb(vout_data_audio), .out_hs(), .out_vs(comfort_vs),
    .out_de(comfort_de), .out_rgb(comfort_rgb)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (comfort_vs),
    .I_de          (comfort_de),
    .I_rgb         (comfort_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// Requested snapshots are sampled into private RAM. No ready signal returns
// to the video path, so a slow or disconnected UART cannot stall HDMI.
thumbnail_capture_bram u_thumbnail_capture (
    .pixel_clk       (video_clk),
    .pixel_rst       (rst_video),
    .video_user      (axis_s_user),
    .video_valid     (axis_s_valid),
    .video_rgb       (axis_s_data),
    .request_toggle  (thumbnail_request_toggle),
    .done_toggle     (thumbnail_done_toggle),
    .frame_id        (thumbnail_frame_id),
    .frame_crc32     (thumbnail_crc32),
    .read_clk        (clk),
    .read_addr       (thumbnail_read_addr),
    .read_data       (thumbnail_read_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_video),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_video),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_video),
    .I_serial_rst       (rst_hdmi_5x),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
