onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv sim/vendor/anlogic/eg_phy_glbl.v sim/vendor/anlogic/eg_phy_bram.v fpga/user_source/hdl_source/ambient_brightness.v fpga/user_source/hdl_source/video_control_arbiter.v fpga/user_source/hdl_source/lesson_subtitle_rom.v fpga/user_source/hdl_source/video_status_font.v fpga/user_source/hdl_source/video_effects_osd.v sim/tb_ambient_brightness.sv
vsim work.tb_ambient_brightness work.glbl
run -all
quit -f
