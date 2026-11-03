onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/SD/seg_scan.v fpga/user_source/hdl_source/learning_seg_status.v sim/tb_seg_scan.sv
vsim work.tb_seg_scan
run -all
quit -f
