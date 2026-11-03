onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/SD/frame_fifo_read_dual.v sim/tb_frame_fifo_read_dual.sv sim/tb_frame_fifo_read_qualification.sv
vsim work.tb_frame_fifo_read_dual
onfinish stop
run -all
quit -sim
vsim work.tb_frame_fifo_read_qualification
onfinish stop
run -all
quit -f
