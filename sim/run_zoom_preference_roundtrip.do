onerror {quit -code 1}
vlib zoom_roundtrip_work
vlog -work zoom_roundtrip_work -sv fpga/user_source/hdl_source/video_control_arbiter.v fpga/user_source/hdl_source/SD/bmp_nearest_scaler.v fpga/user_source/hdl_source/SD/fat32_volume_scanner.v fpga/user_source/hdl_source/SD/fat32_file_reader.v fpga/user_source/hdl_source/SD/fat32_virtual_sector_bridge.v fpga/user_source/hdl_source/SD/sd_card_bmp.v sim/tb_sd_card_bmp_control.sv sim/tb_zoom_preference_roundtrip.sv
vsim zoom_roundtrip_work.tb_zoom_preference_roundtrip
run -all
quit -f
