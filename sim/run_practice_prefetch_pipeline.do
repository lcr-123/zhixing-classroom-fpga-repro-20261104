onerror {quit -code 1}
vlib work
vlog -sv fpga/user_source/hdl_source/SD/spi_master.v fpga/user_source/hdl_source/SD/sd_card_cmd.v fpga/user_source/hdl_source/SD/sd_card_sec_read_write.v
vlog -sv fpga/user_source/hdl_source/SD/bmp_read.v fpga/user_source/hdl_source/SD/bmp_nearest_scaler.v fpga/user_source/hdl_source/SD/fat32_volume_scanner.v fpga/user_source/hdl_source/SD/fat32_file_reader.v fpga/user_source/hdl_source/SD/fat32_virtual_sector_bridge.v fpga/user_source/hdl_source/SD/lesson_voice_reader.v fpga/user_source/hdl_source/SD/sd_card_top.v fpga/user_source/hdl_source/SD/sd_card_bmp.v fpga/user_source/hdl_source/SD/frame_fifo_write.v fpga/user_source/hdl_source/frame_buffer_commit.v sim/tb_practice_prefetch_pipeline.sv
vsim work.tb_practice_prefetch_pipeline
run -all
quit -f
