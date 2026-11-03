set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set source_project_dir [file join $repo_dir fpga td_project]
set source_user_dir [file join $repo_dir fpga user_source]
set workspace_name td_workspace
set opt_area 0
set place_seed ""
if {[info exists ::env(TD_OPT_AREA)]} { set opt_area $::env(TD_OPT_AREA) }
if {[info exists ::env(TD_SEED)]} { set place_seed $::env(TD_SEED) }
if {![string is integer -strict $opt_area] || ($opt_area != 0 && $opt_area != 1) ||
    ($place_seed ne "" && (![string is integer -strict $place_seed] || $place_seed < 1))} {
    puts stderr "BUILD_FAIL invalid TD_OPT_AREA or TD_SEED"
    exit 1
}
if {[info exists ::env(TD_BUILD_WORKSPACE)]} {
    set workspace_name $::env(TD_BUILD_WORKSPACE)
    if {![regexp {^[A-Za-z0-9_-]+$} $workspace_name]} {
        puts stderr "BUILD_FAIL invalid workspace name"
        exit 1
    }
}
set workspace_dir [file join $repo_dir out $workspace_name]
set project_dir [file join $workspace_dir td_project]
set project_file [file join $project_dir HDMI1.4b_Transmitter_v1.0.al]
set source_dir [file join $workspace_dir user_source]
set build_dir [file join $workspace_dir build]
set project_name HDMI1.4b_Transmitter_v1.0

puts "BUILD_INFO project=$project_file"
puts "BUILD_INFO output=$build_dir"

if {[file exists $workspace_dir]} {
    if {[info exists ::env(TD_BUILD_WORKSPACE)]} {
        puts stderr "BUILD_FAIL output directory already exists: $workspace_dir"
        exit 1
    }
    file delete -force $workspace_dir
}
file mkdir $project_dir
file copy -force $source_user_dir $source_dir
file copy -force [file join $source_project_dir HDMI1.4b_Transmitter_v1.0.al] $project_file
file copy -force [file join $source_project_dir al_ip] [file join $project_dir al_ip]
file mkdir $build_dir

proc run_flow {} {
    global project_dir project_file source_dir build_dir project_name opt_area place_seed

    # TD 6.2 resolves .al source paths against the process working directory.
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
    if {$opt_area} {
        set_param gate opt_area high
        set_param gate pack_effort high
    }
    optimize_gate -packarea ${project_name}_gate.area
    legalize_phy_inst
    update_timing
    report_timing_status -file ${project_name}_gate.ts
    report_timing_summary -file ${project_name}_gate.timing
    export_db ${project_name}_gate.db

    puts "BUILD_STEP place"
    if {$place_seed ne ""} { set_param place seed $place_seed }
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

puts "BUILD_PASS td_full_flow"
exit 0
