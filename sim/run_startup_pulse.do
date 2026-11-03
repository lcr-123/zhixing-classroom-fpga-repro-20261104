onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/startup_pulse.v sim/tb_startup_pulse.sv
vsim work.tb_startup_pulse
run -all
quit -f
