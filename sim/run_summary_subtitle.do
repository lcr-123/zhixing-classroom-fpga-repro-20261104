onerror {quit -code 1}
onbreak {quit -code 1}
set stream [open fpga/user_source/hdl_source/top_tf_hdmi_audio.v r]
set top [read $stream]
close $stream
set begin [string first "// Publish the complete application state" $top]
set end [string first "// Synchronize the application state" $top $begin]
if {$begin < 0 || $end < 0} { error "missing production state publisher" }
file mkdir out/summary_subtitle
set stream [open out/summary_subtitle/state_publish.vh w]
puts $stream [string range $top $begin [expr {$end-1}]]
close $stream
vlib work
vlog -sv sim/vendor/anlogic/eg_phy_glbl.v sim/vendor/anlogic/eg_phy_bram.v \
    fpga/user_source/hdl_source/lesson_subtitle_rom.v \
    fpga/user_source/hdl_source/video_status_font.v \
    fpga/user_source/hdl_source/video_effects_osd.v sim/tb_summary_subtitle.sv
vsim work.tb_summary_subtitle work.glbl
run -all
quit -f
