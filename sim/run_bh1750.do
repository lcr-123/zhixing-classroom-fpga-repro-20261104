onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv fpga/user_source/hdl_source/bh1750_reader.v sim/tb_bh1750.sv
vsim work.tb_bh1750
run -all
quit -f
