onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/video_transition_blend.v sim/tb_video_transition_blend.sv
vsim work.tb_video_transition_blend
run -all
quit -f
