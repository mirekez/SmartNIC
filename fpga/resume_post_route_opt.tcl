set script_dir [file normalize [file dirname [info script]]]
set project_file [file join $script_dir build open_switch.xpr]

open_project $project_file

set impl_run [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $impl_run
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore $impl_run
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true $impl_run

# Preserve synthesis, placement, and routing.  Only invalidate the bitstream and
# resume at the previously disabled post-route physical-optimization step.
reset_run $impl_run -from_step {phys_opt_design (Post-Route)}
launch_runs $impl_run -to_step write_bitstream -jobs 1
wait_on_run $impl_run

set status [get_property STATUS $impl_run]
if {$status ne "write_bitstream Complete!"} {
    error "Post-route implementation did not complete: $status"
}

open_run $impl_run
set run_dir [file join $script_dir build open_switch.runs impl_1]
report_timing_summary -max_paths 100 -report_unconstrained \
    -file [file join $run_dir klusterlab_top_timing_summary_postroute_physopt.rpt]
report_drc -file [file join $run_dir klusterlab_top_drc_postroute_physopt.rpt]

foreach extension {bit bin} {
    set source [file join $run_dir klusterlab_top.$extension]
    set destination [file join $script_dir open_switch.$extension]
    if {![file exists $source]} {
        error "Missing implementation artifact: $source"
    }
    file copy -force $source $destination
    puts "FPGA_ARTIFACT=$destination"
}
