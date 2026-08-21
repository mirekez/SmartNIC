set script_dir [file dirname [file normalize [info script]]]
set checkpoint [file join $script_dir build parser_check PacketParser_synth.dcp]
open_checkpoint $checkpoint
create_clock -name net_clk -period 6.400 [get_ports net_clk]

proc report_boundary {label from_pattern to_pattern} {
    set from_cells [get_cells -quiet -hier -filter "NAME =~ $from_pattern"]
    set to_cells [get_cells -quiet -hier -filter "NAME =~ $to_pattern"]
    set paths [get_timing_paths -quiet -delay_type max -from $from_cells \
        -to $to_cells -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} {
        puts "$label=NO_PATH"
        return
    }
    set path [lindex $paths 0]
    puts "$label DELAY=[get_property DATAPATH_DELAY $path] LEVELS=[get_property LOGIC_LEVELS $path] FROM=[get_property STARTPOINT_PIN $path] TO=[get_property ENDPOINT_PIN $path]"
}

report_boundary INGRESS_TO_SCAN "*ingress_*_reg_reg*" "*scan_event_reg_reg*"
report_boundary SCAN_TO_REALIGN "*scan_event_reg_reg*" "*realign_event_reg_reg*"
report_boundary REALIGN_TO_PIPE "*realign_event_reg_reg*" "*pipe_reg_reg*"
