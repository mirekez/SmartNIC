set script_dir [file dirname [file normalize [info script]]]
set checkpoint [file join $script_dir build open_switch.runs impl_1 klusterlab_top_physopt.dcp]
set output_dir [file join $script_dir build uart_probe_route_recovery]

file mkdir $output_dir
set_param general.maxThreads 4

if {![file exists $checkpoint]} {
    error "Missing post-physical-optimization checkpoint: $checkpoint"
}

open_checkpoint $checkpoint
route_design -directive AggressiveExplore

report_route_status -file [file join $output_dir route_status.rpt]
report_timing_summary -file [file join $output_dir timing_summary.rpt]
report_utilization -file [file join $output_dir utilization.rpt]
write_checkpoint -force [file join $output_dir klusterlab_top_routed.dcp]
write_bitstream -force -bin_file [file join $output_dir open_switch.bit]

foreach extension {bit bin} {
    set source [file join $output_dir open_switch.$extension]
    set destination [file join $script_dir open_switch.$extension]
    if {![file exists $source]} {
        error "Missing recovery artifact: $source"
    }
    file copy -force $source $destination
    puts "FPGA_ARTIFACT=$destination"
}
