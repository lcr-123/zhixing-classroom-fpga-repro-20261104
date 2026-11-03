onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/wrong_question_queue.v fpga/user_source/hdl_source/quiz_engine.v sim/tb_quiz_engine.sv
vsim work.tb_quiz_engine
run -all
quit -f
