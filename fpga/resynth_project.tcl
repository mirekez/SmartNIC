# Re-run only top-level synthesis in an existing generated Vivado project.
set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir build open_switch.xpr]
set report_dir [file join $script_dir build]

set_param general.maxThreads 4
set_param synth.maxThreads 4
open_project $project_file
set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on [get_runs synth_1]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
set_property INCREMENTAL_CHECKPOINT {} [get_runs synth_1]
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis did not complete: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $report_dir resynth_hierarchical_utilization.rpt]
report_timing_summary -delay_type max -max_paths 50 \
    -file [file join $report_dir resynth_timing_summary.rpt]
write_checkpoint -force [file join $report_dir resynth_klusterlab_top.dcp]
