onerror {quit -code 1}
onbreak {quit -code 1}

# Exercise the actual top-level routing and request mailbox, rather than a
# second implementation of the wiring. OLD_NAV_TOP supports a negative control.
set source fpga/user_source/hdl_source/top_tf_hdmi_audio.v
if {[info exists ::env(OLD_NAV_TOP)]} { set source $::env(OLD_NAV_TOP) }
set stream [open $source r]
set top [read $stream]
close $stream
file mkdir out/learning_navigation
set stream [open out/learning_navigation/top_routes.vh w]
foreach name {practice_double_click_active settings_zoom_navigation learning_double_click_active key2_single_event nav_next_event nav_prev_event home_long_event} {
    if {[regexp "assign $name =\[^;\]+;" $top statement]} {
        puts $stream $statement
    } elseif {$name ne "learning_double_click_active"} {
        error "missing production assignment $name"
    }
}
if {![regexp {learning_key_double_click u_learning_key_double_click \([^;]+;} $top statement]} {
    error "missing production double-click instance"
}
puts $stream $statement
# Scale the production default at 50 MHz: each test cycle represents 25 ms.
# Derive it from RTL so a later window reduction cannot hide behind defparam.
set key_stream [open fpga/user_source/hdl_source/learning_key_double_click.v r]
set key_source [read $key_stream]
close $key_stream
if {![regexp {parameter integer WINDOW_CYCLES = ([0-9_]+)} $key_source unused window]} {
    error "missing production double-click window"
}
set window [string map {_ ""} $window]
if {$window % 1250000 != 0 || $window / 1250000 > 31} {
    error "production window cannot be represented by navigation fixture"
}
puts $stream "defparam u_learning_key_double_click.WINDOW_CYCLES=[expr {$window / 1250000}];"
puts $stream "defparam u_learning_key_double_click.COUNTER_WIDTH=5;"
set start [string first "always @(posedge clk or posedge rst_ref) begin\n    if (rst_ref) begin\n        app_image_mailbox_ref" $top]
set end [string first "\nlearning_app_core u_learning_app_core" $top $start]
if {$start < 0 || $end < 0} { error "missing production image mailbox" }
puts $stream [string range $top $start [expr {$end - 1}]]
close $stream

vlib work
vlog -sv fpga/user_source/hdl_source/learning_key_double_click.v \
    fpga/user_source/hdl_source/learning_controller.v \
    fpga/user_source/hdl_source/SD/bmp_nearest_scaler.v \
    fpga/user_source/hdl_source/SD/fat32_volume_scanner.v \
    fpga/user_source/hdl_source/SD/fat32_file_reader.v \
    fpga/user_source/hdl_source/SD/fat32_virtual_sector_bridge.v \
    fpga/user_source/hdl_source/SD/sd_card_bmp.v \
    sim/tb_sd_card_bmp_control.sv sim/tb_learning_navigation.sv
vsim work.tb_learning_navigation
run -all
quit -f
