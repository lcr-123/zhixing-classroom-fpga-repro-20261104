
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk / audio_mclk 的命名
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# Persistent auto-mode level uses two pixel-domain stages and a frame-boundary
# commit. Only the source-to-first capture path is excepted.
set_false_path -setup \
    -from [get_regs -nowarn {u_video_control_arbiter/auto_brightness_enable}] \
    -to [get_regs -nowarn {u_video_effects_osd/ambient_enable_meta}]
set_false_path -hold \
    -from [get_regs -nowarn {u_video_control_arbiter/auto_brightness_enable}] \
    -to [get_regs -nowarn {u_video_effects_osd/ambient_enable_meta}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#      音频 PLL     -> u_audio_pll
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]

# ------------------------------------------------------------
# 4. 从原 timing(2).sdc 迁移过来的 HDMI 像素/串行时钟约束
#
#    原文件是：
#      create_clock -name pixel_clk  ... [get_nets {S_pixel_clk}]
#      create_clock -name serial_clk ... [get_nets {S_serial_clk}]
#      set_clock_groups -exclusive ...
#
#    在整合工程里，这两个时钟已经由 video_pll 产生，并通过 derive_clocks 建出来了，
#    所以这里只保留“组关系”，不再重复 create_clock。
#
#    这里沿用原作者的写法，把 video_clk 和 hdmi_5x_clk 设成 exclusive。
#    如果后面 Timing Analyzer 明确显示两者之间需要做同步时序分析，再把这一条去掉。
# ------------------------------------------------------------
set_clock_groups -exclusive \
    -group [get_clocks {video_clk}] \
    -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 5. 音频 I2S 发生器/接收器跨域
#
#    audio_mclk 域里生成 I2S，video_clk 域里做三拍同步采样。
#    这类路径不是普通同步时序路径，直接切掉更合理。
# ------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {video_clk} hdmi_5x_clk sd_card_clk ext_mem_clk]

# ------------------------------------------------------------
# 6. 可选：如果你的 frame_read_write 内部异步 FIFO 已经完全处理好了跨域，
#    且报告里总出现 video_clk / sd_card_clk / ext_mem_clk 之间的大量伪违例，
#    可以打开下面这组异步分组。
#
#    建议先不要开，先看报告；
#    只有确认这些跨域都只经过 FIFO / 同步器时再开。
# ------------------------------------------------------------
# set_clock_groups -asynchronous \
#     -group [get_clocks {sd_card_clk}] \
#     -group [get_clocks {ext_mem_clk}] \
#     -group [get_clocks {video_clk}] \
#     -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 7. Reset release synchronizers
#
# stable_ready asynchronously asserts each domain's three-stage reset
# synchronizer. Its rising edge only enables the synchronous shift of ones,
# so recovery/setup analysis from stable_ready to those ASR pins is not a
# functional data-path check. Keep this exception limited to these 18
# synchronizer registers; do not extend it to downstream reset endpoints.
# ------------------------------------------------------------
set_false_path -setup \
    -from [get_regs -nowarn {u_clock_reset_manager/stable_ready}] \
    -to [get_pins -nowarn {u_clock_reset_manager/*_release_reg[*]*.sr}]

# TD may duplicate the kept stable_ready source during physical reset-network
# optimization and attach the copy directly to an audio-domain SR pin.  The
# source has no functional data fanout: it only asserts the audio release
# synchronizer, whose deassertion is already three audio clocks long.  Cut only
# setup/recovery paths from this reset-source family into audio_mclk; normal
# 50 MHz-to-audio control mailboxes remain timed by the rules below.
set_false_path -setup \
    -from [get_regs -nowarn {u_clock_reset_manager/stable_ready*}] \
    -to [get_clocks {audio_mclk}]

# The lesson PCM FIFO receives the reference-domain reset only as an
# asynchronous assertion source.  Its generated FIFO logic then releases that
# reset through independent two-stage synchronizers in the SD write and audio
# read domains.  Recovery/setup from ref_release to the first synchronizer
# stages is therefore an asynchronous-input check, not a functional data path.
# TD may legally fold either reset synchronizer into equivalent downstream SR
# logic during physical optimization, so constrain this asynchronous reset
# source to the two FIFO clock domains instead of relying on synthesized
# instance names. This still leaves every PCM, subtitle and control data path
# timed normally.
set_false_path -setup \
    -from [get_regs -nowarn {u_clock_reset_manager/ref_release*}] \
    -to [get_clocks {sd_card_clk}]

set_false_path -setup \
    -from [get_regs -nowarn {u_clock_reset_manager/ref_release*}] \
    -to [get_clocks {audio_mclk}]

# The video reader holds its buffer indices and dual-read mode stable for the
# request. frame_fifo_read_dual has explicit meta/sync stages for those fields
# and a three-stage synchronizer for read_req. Cut only the first captures;
# the synchronized payload, request handshake and all SDRAM logic remain timed.
set_false_path -setup \
    -from [get_regs -nowarn {video_timing_data_m0/read_req u_frame_buffer_commit/display_buf_idx[*] u_frame_buffer_commit/transition_buf_idx[*] u_frame_buffer_commit/transition_active}] \
    -to [get_regs -nowarn {frame_read_write_m0/frame_fifo_read_m0/read_req_sync[0] frame_read_write_m0/frame_fifo_read_m0/index_a_meta[*] frame_read_write_m0/frame_fifo_read_m0/index_b_meta[*] frame_read_write_m0/frame_fifo_read_m0/dual_meta}]

# These are asynchronous first captures. Their input hold check is not a
# functional requirement; all mem-clock stages after them remain timed.
set_false_path -hold \
    -from [get_clocks {video_clk}] \
    -to [get_regs -nowarn {frame_read_write_m0/frame_fifo_read_m0/read_req_sync[0] frame_read_write_m0/frame_fifo_read_m0/index_a_meta[*] frame_read_write_m0/frame_fifo_read_m0/index_b_meta[*] frame_read_write_m0/frame_fifo_read_m0/dual_meta}]

# ------------------------------------------------------------
# 8. Sound-lab control mailbox first-stage capture
#
# The source holds the complete payload stable and then toggles a token.  The
# audio side has two kept payload stages and a three-stage toggle synchronizer,
# so only the first capture stage is asynchronous.  Cut exactly those launch
# to first-stage paths; later stages and all functional audio logic remain
# timed normally.
# ------------------------------------------------------------
set_false_path -setup \
    -from [get_regs -nowarn {u_sound_lab_control/lab_active u_sound_lab_control/frequency_select[*] u_sound_lab_control/amplitude_level[*] u_sound_lab_control/waveform_select[*] u_sound_lab_control/muted u_sound_lab_control/song_enable u_sound_lab_control/control_toggle}] \
    -to [get_regs -nowarn {u_hdmi_audio_tone_i2s_64fs/S_lab_active_meta u_hdmi_audio_tone_i2s_64fs/S_lab_frequency_meta[*] u_hdmi_audio_tone_i2s_64fs/S_lab_amplitude_meta[*] u_hdmi_audio_tone_i2s_64fs/S_lab_waveform_meta[*] u_hdmi_audio_tone_i2s_64fs/S_lab_muted_meta u_hdmi_audio_tone_i2s_64fs/S_song_enable_meta u_hdmi_audio_tone_i2s_64fs/S_control_toggle_sync[0]}]

# Learning narration volume uses the same stable-payload/toggle mailbox
# pattern. Cut only source-to-first-stage setup; the ramp and all functional
# audio-domain paths remain timed.
set_false_path -setup \
    -from [get_regs -nowarn {u_lesson_volume_control/volume_level[*] u_lesson_volume_control/control_toggle}] \
    -to [get_regs -nowarn {u_hdmi_audio_tone_i2s_64fs/S_voice_volume_meta[*] u_hdmi_audio_tone_i2s_64fs/S_voice_volume_toggle_sync[0]}]

# The LMV2 SD reader chooses a track only at a block boundary. The stable
# speed mailbox crosses through two payload stages and a three-stage toggle.
set_false_path -setup \
    -from [get_regs -nowarn {u_lesson_volume_control/speed_level[*] u_lesson_volume_control/speed_toggle}] \
    -to [get_regs -nowarn {sd_card_bmp_m0/u_lesson_voice_reader/speed_meta[*] sd_card_bmp_m0/u_lesson_voice_reader/speed_toggle_sync[0]}]
set_false_path -hold \
    -from [get_regs -nowarn {u_lesson_volume_control/speed_level[*] u_lesson_volume_control/speed_toggle}] \
    -to [get_regs -nowarn {sd_card_bmp_m0/u_lesson_voice_reader/speed_meta[*] sd_card_bmp_m0/u_lesson_voice_reader/speed_toggle_sync[0]}]

# Practice navigation cues use independent previous/next toggle tokens. Cut
# only each asynchronous source-to-first-stage capture; later synchronizer
# stages, event detection, bounded DDS and I2S output remain fully timed.
set_false_path -setup \
    -from [get_regs -nowarn {practice_prev_tone_toggle_ref practice_next_tone_toggle_ref}] \
    -to [get_regs -nowarn {u_hdmi_audio_tone_i2s_64fs/S_practice_prev_tone_toggle_sync[0] u_hdmi_audio_tone_i2s_64fs/S_practice_next_tone_toggle_sync[0]}]

# ------------------------------------------------------------
# 9. Lesson narration event mailbox first-stage capture
#
# PCM bytes cross through the generated asynchronous FIFO and retain its
# Gray-pointer constraints.  Only the stable clip index and start/end event
# toggles use this small mailbox; narration_busy independently enters a
# conventional two-flop level synchronizer for music-page sequencing.
# ------------------------------------------------------------
set_false_path -setup \
    -from [get_regs -nowarn {sd_card_bmp_m0/voice_start_toggle sd_card_bmp_m0/voice_end_toggle sd_card_bmp_m0/u_lesson_voice_reader/voice_page[*]}] \
    -to [get_regs -nowarn {u_hdmi_audio_tone_i2s_64fs/S_voice_start_toggle_sync[0] u_hdmi_audio_tone_i2s_64fs/S_voice_end_toggle_sync[0] u_hdmi_audio_tone_i2s_64fs/S_voice_clip_meta[*]}]

# ------------------------------------------------------------
# 10. Narration subtitle mailbox first-stage capture
#
# Cue, clip and active remain stable until the audio domain toggles the event
# token.  The video side has two payload stages and a three-stage token
# synchronizer, then commits the caption only at a frame boundary.  Cut only
# source-to-first-stage setup paths; all later OSD and glyph logic stays timed.
# ------------------------------------------------------------
set_false_path -setup \
    -from [get_regs -nowarn {u_hdmi_audio_tone_i2s_64fs/O_voice_subtitle_active u_hdmi_audio_tone_i2s_64fs/O_voice_subtitle_clip[*] u_hdmi_audio_tone_i2s_64fs/O_voice_subtitle_cue[*] u_hdmi_audio_tone_i2s_64fs/O_voice_subtitle_toggle}] \
    -to [get_regs -nowarn {u_video_effects_osd/lesson_subtitle_active_meta u_video_effects_osd/lesson_subtitle_clip_meta[*] u_video_effects_osd/lesson_subtitle_cue_meta[*] u_video_effects_osd/lesson_subtitle_toggle_sync[0]}]

# The same actual-playback active level also enters a conventional two-flop
# synchronizer in the 50 MHz application domain. Cut only the first capture;
# the synchronized falling-edge detector and page-tag safety logic remain
# fully timed.
set_false_path -setup \
    -from [get_regs -nowarn {u_hdmi_audio_tone_i2s_64fs/O_voice_subtitle_active}] \
    -to [get_regs -nowarn {u_lesson_auto_advance/voice_active_meta}]

set_false_path -hold \
    -from [get_clocks {audio_mclk}] \
    -to [get_regs -nowarn {u_lesson_auto_advance/voice_active_meta}]

# The audio-domain played-to-end level enters the 50 MHz application domain
# through two stages. Only the asynchronous first capture is excepted.
set_false_path -setup \
    -from [get_regs -nowarn {u_lesson_audio_status/played_to_end}] \
    -to [get_regs -nowarn {u_lesson_auto_advance/voice_complete_meta}]
set_false_path -hold \
    -from [get_regs -nowarn {u_lesson_audio_status/played_to_end}] \
    -to [get_regs -nowarn {u_lesson_auto_advance/voice_complete_meta}]

# ------------------------------------------------------------
# 11. TF content-ready level synchronizer first-stage capture
#
# sd_card_bmp asserts this single-bit level only after all twelve cards have
# been discovered.  It is stable after scan completion and enters the 50 MHz
# application domain through a conventional two-flop synchronizer.  Cut only
# the asynchronous first capture; the second stage and all application gating
# remain timed normally.
# ------------------------------------------------------------
set_false_path -setup \
    -to [get_regs -nowarn {content_ready_ref_meta}]

# ------------------------------------------------------------
# 12. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------

# ------------------------------------------------------------
# 13. Learning audio progress/stop mailbox first-stage capture
#
# SD keeps the validated total and clip stable until a later clip starts.
# Audio samples them through two kept payload stages and detects start/stop
# after three kept token stages. Navigation stop is coalesced per clip.
# Only asynchronous launch-to-first-capture setup is excepted; subsequent
# synchronizer stages, progress arithmetic and all functional paths stay timed.
# ------------------------------------------------------------
set_false_path -setup \
    -from [get_regs -nowarn {sd_card_bmp_m0/voice_start_toggle sd_card_bmp_m0/voice_stop_toggle sd_card_bmp_m0/u_lesson_voice_reader/voice_sample_total[*] sd_card_bmp_m0/u_lesson_voice_reader/voice_page[*]}] \
    -to [get_regs -nowarn {u_lesson_audio_status/start_sync[0] u_lesson_audio_status/stop_sync[0] u_lesson_audio_status/total_meta[*] u_lesson_audio_status/clip_meta[*]}]

set_false_path -setup \
    -from [get_regs -nowarn {sd_card_bmp_m0/voice_stop_toggle}] \
    -to [get_regs -nowarn {u_hdmi_audio_tone_i2s_64fs/S_voice_stop_sync[0]}]

# Startup sound is one 50 MHz token captured by the audio-domain three-flop
# synchronizer. Only the first asynchronous setup check is excepted.
set_false_path -setup \
    -to [get_regs -nowarn {u_hdmi_audio_tone_i2s_64fs/S_boot_tone_toggle_sync[0]}]

# Video requests one snapshot at a frame boundary. Audio holds mailbox data
# and ACK until the next request, so two kept payload stages settle before
# the three-stage ACK permits a frame-boundary commit. First captures only.
set_false_path -setup \
    -from [get_regs -nowarn {u_lesson_audio_status/request}] \
    -to [get_regs -nowarn {u_lesson_audio_status/request_sync[0]}]

set_false_path -setup \
    -from [get_regs -nowarn {u_lesson_audio_status/ack u_lesson_audio_status/mailbox[*]}] \
    -to [get_regs -nowarn {u_lesson_audio_status/ack_sync[0] u_lesson_audio_status/payload_meta[*]}]

# The display ACK returns to SD through a kept three-stage toggle synchronizer.
# Only its first capture is asynchronous.
set_false_path -hold \
    -from [get_clocks {video_clk}] \
    -to [get_regs -nowarn {sd_card_bmp_m0/display_ack_sync[0]}]

# UART status is a read-only sideband. Its first sampling stage cannot stall
# HDMI; later status registers and the complete UART datapath remain timed.
set_false_path -hold \
    -from [get_clocks {video_clk}] \
    -to [get_regs -nowarn {debug_uart_m0/event_sync1[13] debug_uart_m0/disp_idx_meta[*] debug_uart_m0/flags_meta[0] debug_uart_m0/flags_meta[5] debug_uart_m0/flags_meta[6]}]

# Numeric learning status receives the existing stable volume mailbox.
# Only asynchronous first captures are exempt; every later pixel stage is timed.
set_false_path -setup \
    -from [get_regs -nowarn {u_lesson_volume_control/volume_level[*] u_lesson_volume_control/control_toggle}] \
    -to [get_regs -nowarn {u_video_effects_osd/volume_meta[*] u_video_effects_osd/volume_toggle_sync[0]}]
set_false_path -hold \
    -from [get_regs -nowarn {u_lesson_volume_control/volume_level[*] u_lesson_volume_control/control_toggle}] \
    -to [get_regs -nowarn {u_video_effects_osd/volume_meta[*] u_video_effects_osd/volume_toggle_sync[0]}]

set_false_path -setup \
    -from [get_regs -nowarn {u_lesson_volume_control/speed_level[*] u_lesson_volume_control/speed_toggle}] \
    -to [get_regs -nowarn {u_video_effects_osd/speed_meta[*] u_video_effects_osd/speed_toggle_sync[0]}]
set_false_path -hold \
    -from [get_regs -nowarn {u_lesson_volume_control/speed_level[*] u_lesson_volume_control/speed_toggle}] \
    -to [get_regs -nowarn {u_video_effects_osd/speed_meta[*] u_video_effects_osd/speed_toggle_sync[0]}]
