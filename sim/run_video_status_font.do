onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv sim/vendor/anlogic/eg_phy_glbl.v sim/vendor/anlogic/eg_phy_bram.v fpga/user_source/hdl_source/video_status_font.v sim/tb_video_status_font.sv
vsim work.tb_video_status_font work.glbl
run -all
quit -f
