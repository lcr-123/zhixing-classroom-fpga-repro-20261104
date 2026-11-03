onerror {quit -code 1}
vlib work
vlog -sv sim/vendor/anlogic/eg_phy_glbl.v sim/vendor/anlogic/eg_phy_bram.v fpga/user_source/hdl_source/lesson_subtitle_rom.v fpga/user_source/hdl_source/video_status_font.v fpga/user_source/hdl_source/video_effects_osd.v fpga/user_source/hdl_source/audio_waveform_overlay.v sim/tb_learning_status_row.sv
vsim work.tb_learning_status_row work.glbl
run -all
quit -f
