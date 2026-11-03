onerror {quit -code 1}
onbreak {quit -code 1}
set input [open fpga/user_source/hdl_source/top_tf_hdmi_audio.v r]
set top [read $input]
close $input
set start [string first "// The first successful self-test exit is the only startup sound event." $top]
set finish [string first "// Carry every accepted HOME entry" $top $start]
if {$start < 0 || $finish < 0} { error "missing production boot-success event" }
file mkdir out/boot_success_tone
set output [open out/boot_success_tone/top_event.vh w]
puts $output [string range $top $start [expr {$finish - 1}]]
close $output
vlib work
vlog -sv fpga/user_source/hdl_source/lesson_subtitle_rom.v fpga/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v sim/tb_boot_success_tone.sv
vsim -c work.tb_boot_success_tone
run -all
quit -f
