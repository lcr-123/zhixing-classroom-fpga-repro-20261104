onerror {quit -code 1}
vlib work
vlog -sv fpga/user_source/hdl_source/SD/fat32_file_reader.v sim/tb_fat32_reader_sector_step.sv
vsim work.tb_fat32_reader_sector_step
run -all
quit -code 0
