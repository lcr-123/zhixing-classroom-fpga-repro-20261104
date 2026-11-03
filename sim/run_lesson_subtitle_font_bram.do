onerror {quit -code 1}
vlib work
vlog -sv sim/vendor/anlogic/eg_phy_glbl.v sim/vendor/anlogic/eg_phy_bram.v fpga/user_source/hdl_source/lesson_subtitle_rom.v sim/tb_lesson_subtitle_font_bram.sv
vsim work.tb_lesson_subtitle_font_bram work.glbl
run -all
quit -f
