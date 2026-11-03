if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vlog -sv fpga/user_source/hdl_source/lesson_subtitle_rom.v fpga/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v
vlog -sv sim/tb_hdmi_audio_tone_i2s_64fs.sv
vsim -c work.tb_hdmi_audio_tone_i2s_64fs
run -all
quit -f
