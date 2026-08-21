# Route the isolated PacketParser checkpoint produced by check_packet_parser.tcl.
# This validates physical delay before spending hours implementing the complete NIC.
set script_dir [file dirname [file normalize [info script]]]
set report_dir [file normalize [file join $script_dir build parser_check]]
set input_dcp [file join $report_dir PacketParser_synth.dcp]

if {![file exists $input_dcp]} {
    error "Missing $input_dcp; run check_packet_parser.tcl first"
}

open_checkpoint $input_dcp
opt_design
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore
phys_opt_design -directive AggressiveExplore

report_route_status -file [file join $report_dir route_status.rpt]
report_utilization -hierarchical -file [file join $report_dir routed_utilization.rpt]
report_timing_summary -delay_type max -max_paths 100 \
    -file [file join $report_dir routed_timing_summary.rpt]
write_checkpoint -force [file join $report_dir PacketParser_routed.dcp]

set paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $paths] != 0} {
    set path [lindex $paths 0]
    puts [format "PACKET_PARSER_ROUTED_WNS_NS %.3f" [get_property SLACK $path]]
    puts [format "PACKET_PARSER_ROUTED_DATAPATH_NS %.3f" \
        [get_property DATAPATH_DELAY $path]]
}
puts "PACKET_PARSER_ROUTED_REPORT_DIR $report_dir"
