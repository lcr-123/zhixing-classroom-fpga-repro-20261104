onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/learning_key_double_click.v sim/tb_learning_key_double_click.sv
vsim work.tb_learning_key_double_click
run -all
quit -f
