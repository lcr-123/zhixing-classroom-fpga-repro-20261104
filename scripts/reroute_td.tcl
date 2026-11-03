set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set workspace_dir [file join $repo_dir out td_workspace]
set project_dir [file join $workspace_dir td_project]
set project_file [file join $project_dir HDMI1.4b_Transmitter_v1.0.al]
set build_dir [file join $workspace_dir build]
set project_name HDMI1.4b_Transmitter_v1.0
set place_seed 1
if {[info exists ::env(TD_PLACE_SEED)]} {
    set place_seed $::env(TD_PLACE_SEED)
}

puts "BUILD_INFO project=$project_file"
puts "BUILD_INFO input=[file join $build_dir ${project_name}_gate.db]"
puts "BUILD_INFO place_seed=$place_seed"

proc run_flow {} {
    global project_dir project_file build_dir project_name place_seed

    cd $project_dir
    import_device eagle_s20.db -package EG4S20BG256
    open_project $project_file -single_run
    load_run_param -run phy_1
    cd $build_dir

    puts "BUILD_STEP import_gate"
    import_db ${project_name}_gate.db

    puts "BUILD_STEP place_seed$place_seed"
    set_param place seed $place_seed
    insert_debugger
    place
    update_timing -mode manhattan
    report_timing_summary -file ${project_name}_place_seed${place_seed}.timing
    report_area -io_info -file ${project_name}_phy.area
    export_db ${project_name}_place_seed${place_seed}.db

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

puts "BUILD_PASS td_seed${place_seed}_reroute"
exit 0
