onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/SD/bmp_nearest_scaler.v sim/tb_bmp_nearest_scaler.sv sim/tb_bmp_nearest_scaler_reference.sv
vsim work.tb_bmp_nearest_scaler
onfinish stop
run -all
quit -sim
vsim work.tb_bmp_nearest_scaler_reference
onfinish stop
run -all
quit -sim
vsim -gPRODUCTION=1 work.tb_bmp_nearest_scaler_reference
onfinish stop
run -all
quit -f
