onerror {quit -code 1}
vlib work
vmap work work
vlog -sv fpga/user_source/hdl_source/sound_lab_control.v
vlog -sv fpga/user_source/hdl_source/lesson_subtitle_rom.v fpga/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v
vlog -sv fpga/user_source/hdl_source/I2S_receiver.v fpga/user_source/hdl_source/audio_arc_calculate.v
vlog -sv sim/tb_music_exercise_audio_path.sv
vsim -c work.tb_music_exercise_audio_path
run -all
quit -code 0
