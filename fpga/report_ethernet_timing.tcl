set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir build open_switch.xpr]
set report_dir [file join $script_dir build]
set checkpoint [file join $script_dir build open_switch.runs impl_1 \
    klusterlab_top_routed.dcp]

if {[file exists $checkpoint]} {
    open_checkpoint $checkpoint
} else {
    open_project $project_file
    open_run impl_1
}

# The CPU clocks are derived from eth_refclk_p, so clock-only filtering also
# selects CPU/L2 paths.  Require both endpoints to be sequential cells in the
# actual Network hierarchy; this is the Ethernet datapath acceptance scope.
set network_seq [get_cells -hierarchical -quiet -filter \
    {NAME =~ nic/network/* && IS_SEQUENTIAL == 1}]
if {[llength $network_seq] == 0} {
    error "No sequential cells found below nic/network"
}

set paths [get_timing_paths -delay_type max -from $network_seq \
    -to $network_seq -max_paths 100 -nworst 1]
if {[llength $paths] == 0} {
    error "No Ethernet-to-Ethernet timing paths found"
}

report_timing -delay_type max -from $network_seq -to $network_seq \
    -max_paths 100 -nworst 1 -input_pins \
    -file [file join $report_dir ethernet_timing.rpt]

set worst_path [lindex $paths 0]
puts "ETHERNET_WNS=[get_property SLACK $worst_path]"
puts "ETHERNET_DATAPATH_DELAY=[get_property DATAPATH_DELAY $worst_path]"
puts "ETHERNET_LOGIC_LEVELS=[get_property LOGIC_LEVELS $worst_path]"
puts "ETHERNET_STARTPOINT=[get_property STARTPOINT_PIN $worst_path]"
puts "ETHERNET_ENDPOINT=[get_property ENDPOINT_PIN $worst_path]"
