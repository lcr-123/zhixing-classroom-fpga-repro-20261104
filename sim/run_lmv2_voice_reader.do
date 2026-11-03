onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv fpga/user_source/hdl_source/SD/lesson_voice_reader.v sim/tb_lmv2_voice_reader.sv
vsim -c work.tb_lmv2_voice_reader
run -all
quit -f
