onerror {quit -code 1}
vlib work
vlog -sv sim/vendor/anlogic/eg_phy_glbl.v sim/vendor/anlogic/eg_phy_bram.v fpga/user_source/hdl_source/learning_keypad.v fpga/user_source/hdl_source/video_control_arbiter.v fpga/user_source/hdl_source/lesson_subtitle_rom.v fpga/user_source/hdl_source/video_status_font.v fpga/user_source/hdl_source/video_effects_osd.v fpga/user_source/hdl_source/video_eye_comfort.v sim/tb_eye_comfort.sv
vsim work.tb_eye_comfort work.glbl
run -all
quit -f
