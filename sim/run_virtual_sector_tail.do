onerror {quit -code 1}
vlib work
vlog -sv fpga/user_source/hdl_source/SD/fat32_file_reader.v fpga/user_source/hdl_source/SD/fat32_virtual_sector_bridge.v sim/tb_virtual_sector_tail.sv
vsim work.tb_virtual_sector_tail
run -all
quit -f
