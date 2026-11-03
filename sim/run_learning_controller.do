onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/learning_controller.v sim/tb_learning_controller.sv
vsim work.tb_learning_controller
run -all
quit -f
