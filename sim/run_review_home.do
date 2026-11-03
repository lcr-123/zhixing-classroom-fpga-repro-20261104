onerror {quit -code 1}
onbreak {quit -code 1}
set source fpga/user_source/hdl_source/top_tf_hdmi_audio.v
if {[info exists ::env(REVIEW_HOME_TOP)]} { set source $::env(REVIEW_HOME_TOP) }
set stream [open $source r]
set top [read $stream]
close $stream
set begin [string first "// Carry every accepted HOME entry" $top]
if {$begin < 0} { set begin [string first "// Carry the return-home request" $top] }
set end [string first "// Exact image routing" $top $begin]
if {$begin < 0 || $end < 0} { error "missing production HOME request block" }
file mkdir out/review_home
set stream [open out/review_home/home_route.vh w]
puts $stream [string range $top $begin [expr {$end-1}]]
if {![regexp {assign sd_home_request = [^;]+;} $top statement]} {
    error "missing production HOME SD request"
}
puts $stream $statement
close $stream
vlib work
vlog -sv fpga/user_source/hdl_source/learning_controller.v \
    fpga/user_source/hdl_source/english_nature_course_rom.v \
    fpga/user_source/hdl_source/english_nature_question_rom.v \
    fpga/user_source/hdl_source/random_three_question_selector.v \
    fpga/user_source/hdl_source/quiz_engine.v \
    fpga/user_source/hdl_source/wrong_question_queue.v \
    fpga/user_source/hdl_source/learning_app_core.v \
    fpga/user_source/hdl_source/SD/bmp_nearest_scaler.v \
    fpga/user_source/hdl_source/SD/fat32_volume_scanner.v \
    fpga/user_source/hdl_source/SD/fat32_file_reader.v \
    fpga/user_source/hdl_source/SD/fat32_virtual_sector_bridge.v \
    fpga/user_source/hdl_source/SD/sd_card_bmp.v \
    sim/tb_sd_card_bmp_control.sv sim/tb_review_home.sv
vsim work.tb_review_home
run -all
quit -f
