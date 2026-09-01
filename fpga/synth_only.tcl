set script_dir [file dirname [file normalize [info script]]]
set_param general.maxThreads 4
set_param synth.maxThreads 4
source [file join $script_dir create_project.tcl]
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis did not complete: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
report_utilization -hierarchical -hierarchical_depth 12 \
    -hierarchical_percentages \
    -file [file join $script_dir build synthesis_hierarchical_utilization.rpt]
report_timing_summary \
    -file [file join $script_dir build synthesis_timing_summary.rpt]
exit
