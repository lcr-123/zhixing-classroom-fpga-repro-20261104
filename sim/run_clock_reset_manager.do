onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/clock_reset_manager.v sim/tb_clock_reset_manager.sv
vsim work.tb_clock_reset_manager
run -all
quit -f
