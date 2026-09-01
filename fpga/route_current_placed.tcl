# Route the checkpoint produced by place_analyze.tcl without discarding its
# expensive placement.  This is useful for preserving an intermediate,
# functional bring-up image before the next architectural timing iteration.
set script_dir [file dirname [file normalize [info script]]]
set input_dcp [file join $script_dir build place_analysis \
    klusterlab_top_placed.dcp]
set output_dir [file join $script_dir build placed_route]
set output_base [file join $output_dir open_switch_cpu_rxbuffer]

if {![file exists $input_dcp]} {
    error "Missing placed checkpoint: $input_dcp"
}
file mkdir $output_dir
set_param general.maxThreads 4

open_checkpoint $input_dcp
phys_opt_design -directive Explore
report_timing_summary -delay_type max -max_paths 100 \
    -file [file join $output_dir timing_physopt.rpt]
write_checkpoint -force [file join $output_dir klusterlab_top_physopt.dcp]

route_design -directive Explore
report_route_status -file [file join $output_dir route_status.rpt]
report_timing_summary -delay_type min_max -max_paths 100 \
    -file [file join $output_dir timing_routed.rpt]
report_design_analysis -congestion \
    -file [file join $output_dir congestion_routed.rpt]
write_checkpoint -force [file join $output_dir klusterlab_top_routed.dcp]

set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
write_bitstream -force -bin_file ${output_base}.bit
foreach extension {bit bin} {
    set source ${output_base}.${extension}
    set destination [file join $script_dir open_switch.${extension}]
    if {![file exists $source]} {
        error "Missing routed artifact: $source"
    }
    file copy -force $source $destination
    puts "FPGA_ARTIFACT=$destination"
}
exit
