onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/SD/bmp_nearest_scaler.v fpga/user_source/hdl_source/SD/fat32_volume_scanner.v fpga/user_source/hdl_source/SD/fat32_file_reader.v fpga/user_source/hdl_source/SD/fat32_virtual_sector_bridge.v fpga/user_source/hdl_source/SD/sd_card_bmp.v sim/tb_sd_card_bmp_control.sv
vsim work.tb_sd_card_bmp_control
run -all
quit -f
