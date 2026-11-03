onerror {quit -code 1}
vlib work
vlog -sv fpga/user_source/hdl_source/SD/bmp_read.v sim/tb_bmp_row_qualification.sv
vsim work.tb_bmp_row_qualification
onfinish stop
run -all
quit -f
