set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set source_project_dir [file join $repo_dir fpga td_project]
set source_user_dir [file join $repo_dir fpga user_source]
set workspace_dir [file join $repo_dir out td_seg_diag_workspace]
set project_dir [file join $workspace_dir td_project]
set project_file [file join $project_dir HDMI1.4b_Transmitter_v1.0.al]
set source_dir [file join $workspace_dir user_source]
set build_dir [file join $workspace_dir build]
set project_name seg_display_diagnostic

puts "BUILD_INFO project=$project_file"
puts "BUILD_INFO output=$build_dir"

if {[file exists $workspace_dir]} {
    file delete -force $workspace_dir
}
file mkdir $project_dir
file copy -force $source_user_dir $source_dir
file copy -force [file join $source_project_dir HDMI1.4b_Transmitter_v1.0.al] $project_file
file copy -force [file join $source_project_dir al_ip] [file join $project_dir al_ip]
file mkdir $build_dir

# Only the copied workspace is modified.  The production source remains in
# normal mode and its existing bitstream is not overwritten.
set diag_top [file join $source_dir hdl_source top_tf_hdmi_audio.v]
set diag_fh [open $diag_top r]
fconfigure $diag_fh -encoding utf-8
set diag_text [read $diag_fh]
close $diag_fh
set diag_old {localparam SEG_DIAG_MODE = 1'b0;}
set diag_new {localparam SEG_DIAG_MODE = 1'b1;}
if {[string first $diag_old $diag_text] < 0} {
    error "SEG_DIAG_MODE production marker not found"
}
set diag_text [string map [list $diag_old $diag_new] $diag_text]
set diag_fh [open $diag_top w]
fconfigure $diag_fh -encoding utf-8
puts -nonewline $diag_fh $diag_text
close $diag_fh

proc run_flow {} {
    global project_dir project_file source_dir build_dir project_name

    cd $project_dir
    import_device eagle_s20.db -package EG4S20BG256
    open_project $project_file -single_run
    load_run_param -run phy_1
    cd $build_dir

    puts "BUILD_STEP read_design"
    elaborate -top top
    read_adc [file join $source_dir constraints_source pin.adc]
    read_sdc [file join $source_dir constraints_source timing.sdc]
    read_sdc -ip rfifo_32_32_512 [file join $source_dir hdl_source IP afifo_32_16_256.tcl]
    read_sdc -ip wfifo_32_32_512 [file join $source_dir hdl_source IP afifo_16_32_256.tcl]
    export_db ${project_name}_elaborate.db

    puts "BUILD_STEP optimize_rtl"
    insert_debugger
    optimize_rtl
    report_area -file ${project_name}_rtl.area
    export_db ${project_name}_rtl.db

    puts "BUILD_STEP optimize_gate"
    optimize_gate -packarea ${project_name}_gate.area
    legalize_phy_inst
    update_timing
    report_timing_status -file ${project_name}_gate.ts
    report_timing_summary -file ${project_name}_gate.timing
    export_db ${project_name}_gate.db

    puts "BUILD_STEP place"
    insert_debugger
    place
    update_timing -mode manhattan
    report_timing_summary -file ${project_name}_place.timing
    report_area -io_info -file ${project_name}_phy.area
    export_db ${project_name}_place.db

    puts "BUILD_STEP route"
    route
    report_area -io_info -file ${project_name}_phy.area
    update_timing -mode final
    report_timing_status -file ${project_name}_phy.ts
    report_timing_summary -file ${project_name}_pr.timing
    report_timing_exception -file ${project_name}_exception.timing
    report_timing_ignored -file ${project_name}_ignored.timing
    export_db ${project_name}_pr.db

    puts "BUILD_STEP bitgen"
    bitgen -bit ${project_name}.bit
    export_bitgen_param -file .bitgen_param.f
    close_project
}

set rc [catch {run_flow} result options]
if {$rc} {
    puts stderr "BUILD_FAIL $result"
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
    exit 1
}

puts "BUILD_PASS seg_display_diagnostic"
exit 0
