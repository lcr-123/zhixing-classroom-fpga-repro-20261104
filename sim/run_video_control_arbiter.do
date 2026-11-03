if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vlog -sv fpga/user_source/hdl_source/video_control_arbiter.v
vlog -sv sim/tb_video_control_arbiter.sv
vsim -c work.tb_video_control_arbiter
run -all
quit -f
