# Re-map an existing RTL checkpoint with dense packing, then place and route.
# First run build_td.tcl. TD_AREA_WORKSPACE optionally selects another folder
# directly under out/; TD_SEED optionally selects a positive placement seed.
set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set workspace_name td_workspace
set seed 8
set output_tag ""
if {[info exists ::env(TD_AREA_WORKSPACE)]} {
    set workspace_name $::env(TD_AREA_WORKSPACE)
}
if {[info exists ::env(TD_SEED)]} {
    set seed $::env(TD_SEED)
}
if {[info exists ::env(TD_AREA_TAG)]} {
    set output_tag $::env(TD_AREA_TAG)
}
if {![regexp {^[A-Za-z0-9_-]+$} $workspace_name] ||
    ![regexp {^[A-Za-z0-9_-]*$} $output_tag] ||
    ![string is integer -strict $seed] || $seed < 1} {
    puts stderr "BUILD_FAIL invalid workspace name or seed"
    exit 1
}
set workspace_dir [file join $repo_dir out $workspace_name]
set project_dir [file join $workspace_dir td_project]
set project_file [file join $project_dir HDMI1.4b_Transmitter_v1.0.al]
set rtl_db [file join $workspace_dir build HDMI1.4b_Transmitter_v1.0_rtl.db]
set output_dir [file join $repo_dir out ${workspace_name}_area_seed${seed}${output_tag}]
set project_name HDMI1.4b_Transmitter_v1.0
if {![file exists $project_file] || ![file exists $rtl_db]} {
    puts stderr "BUILD_FAIL missing project or RTL checkpoint in $workspace_dir"
    exit 1
}
if {[file exists $output_dir]} {
    puts stderr "BUILD_FAIL output directory already exists: $output_dir"
    exit 1
}
file mkdir $output_dir
puts "BUILD_INFO rtl_checkpoint=$rtl_db output=$output_dir seed=$seed"

proc run_area_flow {} {
    global project_dir project_file rtl_db output_dir project_name seed
    cd $project_dir
    import_device eagle_s20.db -package EG4S20BG256
    open_project $project_file -single_run
    load_run_param -run phy_1
    cd $output_dir
    import_db $rtl_db
    set_param gate opt_area high
    set_param gate pack_effort high
    optimize_gate -packarea ${project_name}_gate.area
    legalize_phy_inst
    update_timing
    export_db ${project_name}_gate.db
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
if {[catch {run_area_flow} result options]} {
    puts stderr "BUILD_FAIL $result"
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
    exit 1
}
# A successful tool run still requires a separate setup/hold audit.
puts "BUILD_PASS td_area_seed${seed}"
exit 0
