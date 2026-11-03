onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/learning_keypad.v \
    fpga/user_source/hdl_source/learning_controller.v \
    fpga/user_source/hdl_source/english_nature_course_rom.v \
    fpga/user_source/hdl_source/english_nature_question_rom.v \
    fpga/user_source/hdl_source/random_three_question_selector.v \
    fpga/user_source/hdl_source/quiz_engine.v \
    fpga/user_source/hdl_source/wrong_question_queue.v \
    fpga/user_source/hdl_source/learning_app_core.v \
    sim/tb_learning_app_core.sv
vsim work.tb_learning_app_core
run -all
quit -f
