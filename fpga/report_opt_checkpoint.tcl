# Read an implementation checkpoint and emit hierarchical resource and timing
# diagnostics without modifying the project run that produced the checkpoint.
set script_dir [file dirname [file normalize [info script]]]
set checkpoint [file join $script_dir build open_switch.runs impl_1 klusterlab_top_opt.dcp]
set report_dir [file join $script_dir build opt_checkpoint_reports]

if {$argc > 0} {
    set checkpoint [file normalize [lindex $argv 0]]
}
if {$argc > 1} {
    set report_dir [file normalize [lindex $argv 1]]
}

file mkdir $report_dir
open_checkpoint $checkpoint
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $report_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
report_methodology -file [file join $report_dir methodology.rpt]

# Primitive names expose which generated expressions expanded inside the
# unexpectedly large InputBalancer FIFO controller hierarchy.
set balancer_luts [open [file join $report_dir balancer_lut_cells.txt] w]
foreach cell [get_cells -hierarchical -filter \
        {NAME =~ *balancer* && REF_NAME =~ LUT*}] {
    puts $balancer_luts $cell
}
close $balancer_luts
