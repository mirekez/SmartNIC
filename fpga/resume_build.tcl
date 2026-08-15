set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir build open_switch.xpr]
set_param general.maxThreads 1
set_param synth.maxThreads 1

if {![file exists $project_file]} {
    error "Project does not exist; run fpga/build.sh first"
}

open_project $project_file
# Restore the normal performance-oriented, timing-driven synthesis settings in
# case the project was previously opened for a diagnostic low-memory run.
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on [get_runs synth_1]
set_property {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {} [get_runs synth_1]
set generated_dir [file join [file dirname $script_dir] rtl generated]
foreach source [glob -directory $generated_dir *.sv] {
    if {[llength [get_files -quiet $source]] == 0} {
        add_files -norecurse $source
    }
}
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis did not complete: [get_property STATUS [get_runs synth_1]]"
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation did not complete: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_utilization -file [file join $script_dir build utilization.rpt]
report_timing_summary -file [file join $script_dir build timing_summary.rpt]
file copy -force \
    [file join $script_dir build open_switch.runs impl_1 klusterlab_top.bit] \
    [file join $script_dir open_switch.bit]
puts "BITSTREAM=[file join $script_dir open_switch.bit]"
