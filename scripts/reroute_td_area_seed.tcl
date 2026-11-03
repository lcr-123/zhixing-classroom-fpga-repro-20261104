set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set project_workspace td_workspace
if {[info exists ::env(TD_AREA_PROJECT_WORKSPACE)]} {
    set project_workspace $::env(TD_AREA_PROJECT_WORKSPACE)
}
if {![regexp {^[A-Za-z0-9_-]+$} $project_workspace]} {
    puts stderr "REROUTE_FAIL invalid project workspace"
    exit 1
}
set project_dir [file join $repo_dir out $project_workspace td_project]
set project_file [file join $project_dir HDMI1.4b_Transmitter_v1.0.al]
set gate_workspace td_workspace_area_seed8
if {[info exists ::env(TD_AREA_GATE_WORKSPACE)]} {
    set gate_workspace $::env(TD_AREA_GATE_WORKSPACE)
}
if {![regexp {^[A-Za-z0-9_-]+$} $gate_workspace]} {
    puts stderr "REROUTE_FAIL invalid gate workspace"
    exit 1
}
set gate_db [file join $repo_dir out $gate_workspace HDMI1.4b_Transmitter_v1.0_gate.db]
set project_name HDMI1.4b_Transmitter_v1.0
set seed 8
if {[info exists ::env(TD_SEED)]} { set seed $::env(TD_SEED) }
if {![string is integer -strict $seed] || $seed < 1} {
    puts stderr "REROUTE_FAIL TD_SEED must be a positive integer"
    exit 1
}
if {![file exists $project_file] || ![file exists $gate_db]} {
    puts stderr "REROUTE_FAIL missing project or area gate database"
    exit 1
}
set output_dir [file join $repo_dir out ${gate_workspace}_reroute_$seed]
if {[file exists $output_dir]} {
    puts stderr "REROUTE_FAIL output directory already exists: $output_dir"
    exit 1
}
file mkdir $output_dir
proc run_flow {} {
    global project_dir project_file gate_db project_name output_dir seed
    cd $project_dir
    import_device eagle_s20.db -package EG4S20BG256
    open_project $project_file -single_run
    load_run_param -run phy_1
    cd $output_dir
    import_db $gate_db
    set_param place seed $seed
    insert_debugger
    place
    update_timing -mode manhattan
    report_timing_summary -file ${project_name}_place.timing
    report_area -io_info -file ${project_name}_place.area
    export_db ${project_name}_place.db
    route
    report_area -io_info -file ${project_name}_phy.area
    update_timing -mode final
    report_timing_status -file ${project_name}_phy.ts
    report_timing_summary -file ${project_name}_pr.timing
    report_timing_exception -file ${project_name}_exception.timing
    report_timing_ignored -file ${project_name}_ignored.timing
    export_db ${project_name}_pr.db
    bitgen -bit ${project_name}.bit
    export_bitgen_param -file .bitgen_param.f
    close_project
}
if {[catch {run_flow} result options]} {
    puts stderr "REROUTE_FAIL $result"
    if {[dict exists $options -errorinfo]} { puts stderr [dict get $options -errorinfo] }
    exit 1
}
puts "BUILD_PASS td_area_seed${seed}"
exit 0
