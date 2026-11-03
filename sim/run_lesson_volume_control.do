if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vlog -sv fpga/user_source/hdl_source/lesson_volume_control.v sim/tb_lesson_volume_control.sv
vsim -c work.tb_lesson_volume_control
run -all
quit -f
