onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/learning_keypad.v fpga/user_source/hdl_source/learning_key_double_click.v fpga/user_source/hdl_source/video_control_arbiter.v sim/tb_learning_keypad.sv sim/tb_key_navigation_integration.sv
vsim work.tb_learning_keypad
onfinish stop
run -all
quit -sim
vsim work.tb_key_navigation_integration
onfinish stop
run -all
quit -f
