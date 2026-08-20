set script_dir [file dirname [file normalize [info script]]]
open_checkpoint [file join $script_dir build resynth_klusterlab_top.dcp]

foreach cell [get_cells -hier -filter {NAME =~ *network/balancer/*/mem}] {
    puts "MEMORY_CELL [get_property NAME $cell] REF=[get_property REF_NAME $cell] ORIG=[get_property ORIG_REF_NAME $cell]"
    report_utilization -cells $cell
    report_property $cell
}

report_timing -from [get_cells -hier -filter {NAME =~ *network/balancer/*/mem/*}] \
    -to [get_cells -hier -filter {NAME =~ *network/balancer/*/mem/*}] \
    -delay_type max -max_paths 5 -file [file join $script_dir build balancer_memory_timing.rpt]
