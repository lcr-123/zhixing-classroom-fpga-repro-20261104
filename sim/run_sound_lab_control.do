if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vlog -sv fpga/user_source/hdl_source/sound_lab_control.v
vlog -sv sim/tb_sound_lab_control.sv
vsim -c work.tb_sound_lab_control
run -all
quit -f
