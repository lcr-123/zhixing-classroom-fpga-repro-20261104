onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/english_task_quiz_rom.v sim/tb_english_task_quiz_rom.sv
vsim work.tb_english_task_quiz_rom
run -all
quit -f
