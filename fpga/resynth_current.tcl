# Re-synthesize the current generated/source RTL while retaining completed
# out-of-context Ethernet and PCIe IP runs in the existing project.
set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir build open_switch.xpr]
set report_dir [file join $script_dir build]

set_param general.maxThreads 4
set_param synth.maxThreads 4
open_project $project_file
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis did not complete: [get_property STATUS [get_runs synth_1]]"
}

open_run synth_1
report_utilization -hierarchical -hierarchical_depth 12 \
    -hierarchical_percentages \
    -file [file join $report_dir synthesis_hierarchical_utilization.rpt]
report_timing_summary \
    -file [file join $report_dir synthesis_timing_summary.rpt]
exit
