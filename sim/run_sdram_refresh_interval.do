onerror {quit -code 1}
vlib work
exec python scripts/extract_sdram_refresh_frontend.py
vlog -sv +incdir+fpga/user_source/hdl_source/include out/sdram_refresh_frontend.v sim/tb_sdram_refresh_interval.sv
vsim work.tb_sdram_refresh_interval
run -all
quit -f
