# Re-place and route the already synthesized SmartNIC with directives intended
# for a dense, locally congested 7-series design.  Run from fpga/ after a build
# has produced build/open_switch.runs/impl_1/klusterlab_top_opt.dcp.

set script_dir [file normalize [file dirname [info script]]]
set impl_dir [file join $script_dir build open_switch.runs impl_1]
set output_dir [file join $script_dir congestion_retry]
file mkdir $output_dir

set opt_dcp [file join $impl_dir klusterlab_top_opt.dcp]
if {![file exists $opt_dcp]} {
    error "Missing synthesized/optimized checkpoint: $opt_dcp"
}

open_checkpoint $opt_dcp

place_design -directive AltSpreadLogic_high
report_utilization -file [file join $output_dir utilization_placed.rpt]
report_timing_summary -file [file join $output_dir timing_placed.rpt]
write_checkpoint -force [file join $output_dir klusterlab_top_placed.dcp]

phys_opt_design -directive Explore
report_timing_summary -file [file join $output_dir timing_physopt.rpt]
write_checkpoint -force [file join $output_dir klusterlab_top_physopt.dcp]

route_design -directive AlternateCLBRouting
report_route_status -file [file join $output_dir route_status.rpt]
report_timing_summary -file [file join $output_dir timing_routed.rpt]
write_checkpoint -force [file join $output_dir klusterlab_top_routed.dcp]

phys_opt_design -directive Explore
report_route_status -file [file join $output_dir route_status_post_physopt.rpt]
report_timing_summary -file [file join $output_dir timing_post_physopt.rpt]
write_checkpoint -force [file join $output_dir klusterlab_top_post_physopt.dcp]

set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
write_bitstream -force -bin_file [file join $output_dir open_switch_uart_probe.bit]
