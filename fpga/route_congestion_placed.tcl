# Route the congestion-oriented placement saved by retry_congestion_route.tcl.
# The standalone script makes the expensive placement independently resumable.

set script_dir [file normalize [file dirname [info script]]]
set input_dcp [file join $script_dir congestion_retry klusterlab_top_placed.dcp]
set output_dir [file join $script_dir congestion_retry]
if {![file exists $input_dcp]} {
    error "Missing congestion-oriented placement: $input_dcp"
}

open_checkpoint $input_dcp
route_design -directive AlternateCLBRouting
report_route_status -file [file join $output_dir route_status.rpt]
report_timing_summary -file [file join $output_dir timing_routed.rpt]
write_checkpoint -force [file join $output_dir klusterlab_top_routed.dcp]

set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
write_bitstream -force -bin_file \
    [file join $output_dir full_open_switch_uart_probe.bit]
