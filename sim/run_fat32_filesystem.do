onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/SD/fat32_volume_scanner.v fpga/user_source/hdl_source/SD/fat32_file_reader.v fpga/user_source/hdl_source/SD/fat32_virtual_sector_bridge.v sim/tb_fat32_filesystem.sv sim/tb_fat32_root_schedule.sv
vsim work.tb_fat32_filesystem
onfinish stop
run -all
quit -sim
vsim work.tb_fat32_root_schedule
onfinish stop
run -all
quit -f
