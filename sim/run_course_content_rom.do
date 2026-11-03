onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/course_content_rom.v sim/tb_course_content_rom.sv
vsim work.tb_course_content_rom
run -all
quit -f
