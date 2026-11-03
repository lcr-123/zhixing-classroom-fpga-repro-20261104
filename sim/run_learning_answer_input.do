onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/learning_answer_input.v \
    sim/tb_learning_answer_input.sv
vsim work.tb_learning_answer_input
run -all
quit -f
