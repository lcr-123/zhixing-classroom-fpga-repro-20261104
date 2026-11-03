onerror {quit -code 1}
vlib work
vlog -sv sim/vendor/anlogic/eg_phy_glbl.v sim/vendor/anlogic/eg_phy_bram.v fpga/user_source/hdl_source/random_three_question_selector.v fpga/user_source/hdl_source/lesson_subtitle_rom.v fpga/user_source/hdl_source/video_status_font.v fpga/user_source/hdl_source/video_effects_osd.v sim/tb_practice_page_display.sv
vsim work.tb_practice_page_display work.glbl
run -all
quit -f
