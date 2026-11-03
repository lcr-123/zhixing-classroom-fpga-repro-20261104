onerror {quit -code 1}

vlib work
vlog -sv fpga/user_source/hdl_source/audio_waveform_overlay.v sim/tb_audio_waveform_read_ce.sv
vsim work.tb_audio_waveform_read_ce
run -all
quit -f
