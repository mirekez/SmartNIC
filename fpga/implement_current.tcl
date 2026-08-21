# Implement the current synthesized project without recreating IP or sources.
set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir build open_switch.xpr]
set report_dir [file join $script_dir build]

set_param general.maxThreads 4
open_project $project_file
set_property strategy Performance_Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED false [get_runs impl_1]
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
reset_run impl_1
# An interrupted parent Vivado can leave synth_1 marked Running even though its
# worker is gone. Reset synthesis only when it is not already complete; a valid
# completed DCP can be reused when only implementation-time XDC changed.
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    reset_run synth_1
}
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1

set status [get_property STATUS [get_runs impl_1]]
if {$status ne "write_bitstream Complete!"} {
    error "Implementation did not complete: $status"
}

open_run impl_1
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $report_dir implemented_utilization.rpt]
report_timing_summary -delay_type max -max_paths 100 \
    -file [file join $report_dir implemented_timing_summary.rpt]
report_clock_utilization \
    -file [file join $report_dir implemented_clock_utilization.rpt]
report_cdc -details \
    -file [file join $report_dir implemented_cdc.rpt]

set run_dir [file join $script_dir build open_switch.runs impl_1]
foreach extension {bit bin ltx} {
    set source [file join $run_dir klusterlab_top.$extension]
    set destination [file join $script_dir open_switch.$extension]
    if {![file exists $source]} {
        error "Missing implementation artifact: $source"
    }
    file copy -force $source $destination
    puts "FPGA_ARTIFACT=$destination"
}
