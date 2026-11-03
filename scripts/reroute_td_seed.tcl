set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set project_dir [file join $repo_dir out td_workspace td_project]
set project_file [file join $project_dir HDMI1.4b_Transmitter_v1.0.al]
set gate_db [file join $repo_dir out td_workspace build HDMI1.4b_Transmitter_v1.0_gate.db]
set project_name HDMI1.4b_Transmitter_v1.0

if {[info exists ::env(TD_SEED)]} {
    set seed $::env(TD_SEED)
} else {
    set seed 8
}

if {![string is integer -strict $seed] || $seed < 1} {
    puts stderr "REROUTE_FAIL TD_SEED must be a positive integer"
    exit 1
}
if {![file exists $project_file]} {
    puts stderr "REROUTE_FAIL missing project: $project_file"
    exit 1
}
if {![file exists $gate_db]} {
    puts stderr "REROUTE_FAIL missing gate database: $gate_db"
    exit 1
}

set output_dir [file join $repo_dir out td_seed_$seed]
puts "REROUTE_INFO seed=$seed"
puts "REROUTE_INFO gate_db=$gate_db"
puts "REROUTE_INFO output=$output_dir"

if {[file exists $output_dir]} {
    file delete -force $output_dir
}
file mkdir $output_dir

proc run_seed_reroute {} {
    global project_dir project_file gate_db project_name output_dir seed

    cd $project_dir
    import_device eagle_s20.db -package EG4S20BG256
    open_project $project_file -single_run
    load_run_param -run phy_1
    cd $output_dir
    import_db $gate_db
    set_param place seed $seed

    puts "REROUTE_STEP place"
    insert_debugger
    place
    update_timing -mode manhattan
    report_timing_summary -file ${project_name}_place.timing
    report_area -io_info -file ${project_name}_place.area
    export_db ${project_name}_place.db

    puts "REROUTE_STEP route"
    route
    report_area -io_info -file ${project_name}_phy.area
    update_timing -mode final
    report_timing_status -file ${project_name}_phy.ts
    report_timing_summary -file ${project_name}_pr.timing
    report_timing_exception -file ${project_name}_exception.timing
    report_timing_ignored -file ${project_name}_ignored.timing
    export_db ${project_name}_pr.db

    puts "REROUTE_STEP bitgen"
    bitgen -bit ${project_name}.bit
    export_bitgen_param -file .bitgen_param.f
    close_project
}

set rc [catch {run_seed_reroute} result options]
if {$rc} {
    puts stderr "REROUTE_FAIL $result"
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
    exit 1
}

puts "BUILD_PASS td_seed${seed}_reroute"
exit 0
