onerror {quit -code 1}
onbreak {quit -code 1}
set stream [open fpga/user_source/hdl_source/top_tf_hdmi_audio.v r]
set top [read $stream]
close $stream
file mkdir out/review_feedback_image
set stream [open out/review_feedback_image/routes.vh w]
set begin [string first "// Carry every accepted HOME entry" $top]
set end [string first "// Exact image routing" $top $begin]
if {$begin < 0 || $end < 0} { error "missing production HOME route" }
puts $stream [string range $top $begin [expr {$end-1}]]
set begin [string first "assign app_image_context_active =" $top]
set end [string first "\nlearning_app_core u_learning_app_core" $top $begin]
if {$begin < 0 || $end < 0} { error "missing production image route/mailbox" }
puts $stream [string range $top $begin [expr {$end-1}]]
foreach name {sd_home_request sd_app_image_request} {
    if {![regexp "assign $name =\[^;\]+;" $top statement]} {
        error "missing production SD assignment $name"
    }
    puts $stream $statement
}
close $stream
set app fpga/user_source/hdl_source/learning_app_core.v
if {[info exists ::env(REVIEW_FEEDBACK_APP)]} { set app $::env(REVIEW_FEEDBACK_APP) }
vlib work
vlog -sv fpga/user_source/hdl_source/learning_controller.v \
    fpga/user_source/hdl_source/english_nature_course_rom.v \
    fpga/user_source/hdl_source/english_nature_question_rom.v \
    fpga/user_source/hdl_source/random_three_question_selector.v \
    fpga/user_source/hdl_source/quiz_engine.v \
    fpga/user_source/hdl_source/wrong_question_queue.v $app \
    fpga/user_source/hdl_source/SD/bmp_nearest_scaler.v \
    fpga/user_source/hdl_source/SD/fat32_volume_scanner.v \
    fpga/user_source/hdl_source/SD/fat32_file_reader.v \
    fpga/user_source/hdl_source/SD/fat32_virtual_sector_bridge.v \
    fpga/user_source/hdl_source/SD/sd_card_bmp.v \
    sim/tb_sd_card_bmp_control.sv sim/tb_review_feedback_image.sv
vsim work.tb_review_feedback_image
run -all
quit -f
