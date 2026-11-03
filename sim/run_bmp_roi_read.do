onerror {quit -code 1}
vlib work
vlog -sv fpga/user_source/hdl_source/SD/bmp_read.v fpga/user_source/hdl_source/SD/bmp_nearest_scaler.v sim/tb_bmp_roi_read.sv sim/tb_bmp_roi_failures.sv
vsim work.tb_bmp_roi_failures
onfinish stop
run -all
quit -sim
vsim work.tb_bmp_roi_read
onfinish stop
run -all
quit -sim
vsim -gPRODUCTION=1 work.tb_bmp_roi_read
onfinish stop
run -all
quit -f
