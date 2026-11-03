onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/SD/frame_fifo_write.v sim/tb_frame_fifo_write.sv
vsim work.tb_frame_fifo_write
onfinish stop
run -all
puts {TEST_PASS tb_frame_fifo_write}
quit -f
