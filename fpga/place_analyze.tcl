# Stop after placement so a congested floorplan can be rejected in minutes
# instead of spending hours in the router. This script reuses the completed
# synthesis run in fpga/build/open_switch.xpr.
set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir build open_switch.xpr]
set report_dir [file join $script_dir build place_analysis]
set placed_run_dcp [file join $script_dir build open_switch.runs impl_1 \
    klusterlab_top_placed.dcp]

file mkdir $report_dir
set_param general.maxThreads 4
open_project $project_file

if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} {
    error "Synthesis must complete before place_analyze.tcl is run"
}

set_property strategy Performance_Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set reuse_placement [expr {[info exists ::env(SMARTNIC_REUSE_PLACEMENT)]
    && $::env(SMARTNIC_REUSE_PLACEMENT) eq "1"}]
if {!$reuse_placement || ![file exists $placed_run_dcp]} {
    reset_run impl_1
    launch_runs impl_1 -to_step place_design -jobs 1
    wait_on_run impl_1
}

# A run stopped exactly at place_design reports "Not started phys_opt_design"
# rather than "Complete". The placed checkpoint is the reliable completion
# artifact for this intentionally partial implementation run.
if {![file exists $placed_run_dcp]} {
    error "Placement did not complete: [get_property STATUS [get_runs impl_1]]"
}

# A run intentionally stopped after place_design is not considered an openable
# implementation run by every Vivado release.  The placed checkpoint is both
# the completion test above and the canonical analysis input, so use it in
# both the fresh and reuse paths.
open_checkpoint $placed_run_dcp
write_checkpoint -force [file join $report_dir klusterlab_top_placed.dcp]
report_utilization -hierarchical -hierarchical_depth 12 \
    -hierarchical_percentages \
    -file [file join $report_dir hierarchical_utilization.rpt]
report_timing_summary -delay_type max -max_paths 100 \
    -file [file join $report_dir timing_summary.rpt]
report_design_analysis -congestion \
    -file [file join $report_dir congestion.rpt]
report_high_fanout_nets -timing -load_types -max_nets 200 \
    -file [file join $report_dir high_fanout.rpt]
exit
