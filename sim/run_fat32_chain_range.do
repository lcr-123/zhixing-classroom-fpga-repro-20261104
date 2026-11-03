onerror {quit -code 1}
vlib work
vlog -sv fpga/user_source/hdl_source/SD/fat32_file_reader.v sim/tb_fat32_chain_range.sv
vsim work.tb_fat32_chain_range
onfinish stop
run -all
quit -f
