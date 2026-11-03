onerror {quit -code 1}
vlib work
vlog -sv fpga/user_source/hdl_source/lesson_audio_status.v sim/tb_lesson_audio_status.sv
vsim work.tb_lesson_audio_status
run -all
quit -f
