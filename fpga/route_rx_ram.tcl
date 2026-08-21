# Route the isolated RxRAM checkpoint produced by check_rx_ram.tcl.
set script_dir [file dirname [file normalize [info script]]]
set report_dir [file normalize [file join $script_dir build rx_ram_check]]
set input_dcp [file join $report_dir RxRAM_synth.dcp]

if {![file exists $input_dcp]} {
    error "Missing $input_dcp; run check_rx_ram.tcl first"
}

open_checkpoint $input_dcp
opt_design
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore

report_route_status -file [file join $report_dir route_status.rpt]
report_utilization -hierarchical -file [file join $report_dir routed_utilization.rpt]
report_timing_summary -delay_type max -max_paths 100 \
    -file [file join $report_dir routed_timing_summary.rpt]
write_checkpoint -force [file join $report_dir RxRAM_routed.dcp]

set paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $paths] != 0} {
    set path [lindex $paths 0]
    puts [format "RX_RAM_ROUTED_WNS_NS %.3f" [get_property SLACK $path]]
    puts [format "RX_RAM_ROUTED_DATAPATH_NS %.3f" \
        [get_property DATAPATH_DELAY $path]]
    puts "RX_RAM_ROUTED_STARTPOINT [get_property STARTPOINT_PIN $path]"
    puts "RX_RAM_ROUTED_ENDPOINT [get_property ENDPOINT_PIN $path]"
}
puts "RX_RAM_ROUTED_REPORT_DIR $report_dir"
