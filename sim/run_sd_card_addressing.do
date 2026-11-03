onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/SD/sd_card_cmd.v fpga/user_source/hdl_source/SD/sd_card_sec_read_write.v sim/tb_sd_card_addressing.sv
vsim work.tb_sd_card_addressing
run -all
quit -f
