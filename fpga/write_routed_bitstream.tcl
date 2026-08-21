set script_dir [file dirname [file normalize [info script]]]
set run_dir [file join $script_dir build open_switch.runs impl_1]
set checkpoint [file join $run_dir klusterlab_top_routed.dcp]

if {![file exists $checkpoint]} {
    error "Missing routed checkpoint: $checkpoint"
}

open_checkpoint $checkpoint
set bitstream [file join $run_dir klusterlab_top.bit]
set probes [file join $run_dir klusterlab_top.ltx]
write_bitstream -force -bin_file $bitstream
write_debug_probes -force $probes

foreach extension {bit bin ltx} {
    set source [file join $run_dir klusterlab_top.$extension]
    set destination [file join $script_dir open_switch.$extension]
    if {![file exists $source]} {
        error "Missing generated artifact: $source"
    }
    file copy -force $source $destination
    puts "FPGA_ARTIFACT=$destination"
}
