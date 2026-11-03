onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv fpga/user_source/hdl_source/lesson_subtitle_rom.v fpga/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v fpga/user_source/hdl_source/I2S_receiver.v fpga/user_source/hdl_source/audio_waveform_overlay.v sim/tb_lesson_speed_audio.sv
vsim -c work.tb_lesson_speed_audio
run -all
quit -f
