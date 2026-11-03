onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/frame_buffer_commit.v sim/tb_frame_buffer_commit_fast.sv
vsim work.tb_frame_buffer_commit_fast
run -all
quit -f
