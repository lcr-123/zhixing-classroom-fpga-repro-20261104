onerror {quit -code 1}
vlib work
vlog -sv fpga/user_source/hdl_source/SD/bmp_nearest_scaler.v sim/tb_bmp_filtered_scaler.sv
vsim work.tb_bmp_filtered_scaler
onfinish stop
run -all
quit -sim
vsim -gPRODUCTION=1 work.tb_bmp_filtered_scaler
onfinish stop
run -all
quit -sim
vsim -gFOCUS_LEFT=1 work.tb_bmp_filtered_scaler
onfinish stop
run -all
quit -sim
vsim -gPRODUCTION=1 -gFOCUS_LEFT=1 work.tb_bmp_filtered_scaler
onfinish stop
run -all
quit -f
