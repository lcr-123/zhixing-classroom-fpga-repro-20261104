onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/SD/lesson_voice_reader.v sim/tb_lesson_voice_reader.sv
vsim work.tb_lesson_voice_reader
run -all
quit -f
