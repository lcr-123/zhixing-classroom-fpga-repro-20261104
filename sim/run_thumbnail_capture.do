onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/thumbnail_capture_bram.v sim/tb_thumbnail_capture.sv
vsim work.tb_thumbnail_capture
onfinish stop
run -all
quit -sim
# Exercise 80x60 production data: ten 512-word banks, padded tail inaccessible.
vsim -gSOURCE_WIDTH=640 -gSOURCE_HEIGHT=480 -gSAMPLE_SHIFT=3 work.tb_thumbnail_capture
run -all
quit -f
