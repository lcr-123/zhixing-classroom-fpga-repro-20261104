transcript file sim/english_nature_metadata.log
vlib work
vmap work work
vlog -sv fpga/user_source/hdl_source/english_nature_course_rom.v fpga/user_source/hdl_source/english_nature_question_rom.v fpga/user_source/hdl_source/random_three_question_selector.v sim/tb_english_nature_metadata.sv
vsim -c work.tb_english_nature_metadata
run -all
quit -f
