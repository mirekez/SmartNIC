set script_dir [file dirname [file normalize [info script]]]
set checkpoint [file join $script_dir build open_switch.runs impl_1 \
    klusterlab_top_opt.dcp]
set report_dir [file join $script_dir build]

open_checkpoint $checkpoint
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $report_dir optimized_hierarchical_utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $report_dir optimized_timing_summary.rpt]
puts "OPT_HIERARCHY_REPORT=[file join $report_dir optimized_hierarchical_utilization.rpt]"
