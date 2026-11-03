onerror {quit -code 1}
vlib work
vmap work work
vlog -sv fpga/user_source/hdl_source/lesson_auto_advance.v sim/tb_lesson_auto_advance.sv
vsim -c work.tb_lesson_auto_advance
run -all
quit -code 0
