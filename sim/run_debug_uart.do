onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/uart_tx.v fpga/user_source/hdl_source/uart_rx.v fpga/user_source/hdl_source/debug_uart.v sim/tb_debug_uart.sv
vsim work.tb_debug_uart
onfinish stop
run -all
puts {TEST_PASS tb_debug_uart}
quit -f
