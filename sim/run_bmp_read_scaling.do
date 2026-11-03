onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/SD/bmp_read.v sim/tb_bmp_read_scaling.sv
vsim work.tb_bmp_read_scaling
run -all
quit -f
