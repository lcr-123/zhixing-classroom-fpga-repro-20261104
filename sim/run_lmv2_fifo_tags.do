onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv fpga/user_source/hdl_source/IP/afifo_16_32_256.v sim/tb_lmv2_fifo_tags.sv
vsim -c work.tb_lmv2_fifo_tags
run -all
quit -f
