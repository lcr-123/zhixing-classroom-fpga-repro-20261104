onerror {quit -code 1}
vlib work
vlog -sv fpga/user_source/hdl_source/lesson_subtitle_rom.v fpga/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v fpga/user_source/hdl_source/I2S_receiver.v sim/tb_lesson_voice_fade.sv
vsim work.tb_lesson_voice_fade
run -all
quit -f
