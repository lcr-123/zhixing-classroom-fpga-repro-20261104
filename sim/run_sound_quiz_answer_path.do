if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv fpga/user_source/hdl_source/learning_answer_input.v
vlog -sv fpga/user_source/hdl_source/quiz_engine.v
vlog -sv fpga/user_source/hdl_source/sound_quiz_game.v
vlog -sv sim/tb_sound_quiz_answer_path.sv
vsim -c work.tb_sound_quiz_answer_path
run -all
quit -f
