onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/SD/bmp_read.v sim/tb_bmp_scan_fast_start.sv
vsim work.tb_bmp_scan_fast_start
run -all
quit -f
