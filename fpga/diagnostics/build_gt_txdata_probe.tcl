# Post-route UART-only observation image for the physical GTX transmit inputs.
# The normal UART probe samples these nets asynchronously at 50 MHz.  A dump
# is therefore sufficient to prove that each 32-bit gearbox input is changing;
# no ILA/JTAG connection is required.
set script_dir [file normalize [file dirname [info script]]]
set source_dcp [file join $script_dir build uart_10g_probe \
    uart_10g_probe.runs impl_1 uart_10g_probe_top_routed.dcp]

proc attach_probe_bit {probe_bit source_pin} {
    set target [get_pins -quiet uart_probe/probe_in\[$probe_bit\]]
    if {[llength $target] != 1} {
        error "UART probe bit $probe_bit was not preserved"
    }
    set source_net [get_nets -quiet -of_objects $source_pin]
    if {[llength $source_net] != 1} {
        error "No unique source net for $source_pin"
    }
    set old_net [get_nets -quiet -of_objects $target]
    if {[llength $old_net] == 1} {
        disconnect_net -net $old_net -objects $target
    }
    connect_net -hierarchical -net $source_net -objects $target
}

open_checkpoint $source_dcp
set gts [lsort [get_cells -hierarchical -filter {REF_NAME == GTXE2_CHANNEL}]]
if {[llength $gts] != 2} { error "Expected two Ethernet GTX channels" }

set lane 0
foreach gt $gts {
    for {set bit 0} {$bit < 32} {incr bit} {
        set source [get_pins -of_objects $gt -filter \
            "REF_PIN_NAME == TXDATA\[$bit\]"]
        attach_probe_bit [expr {$lane * 32 + $bit}] $source
    }
    for {set bit 0} {$bit < 3} {incr bit} {
        set source [get_pins -of_objects $gt -filter \
            "REF_PIN_NAME == TXHEADER\[$bit\]"]
        attach_probe_bit [expr {64 + $lane * 3 + $bit}] $source
    }
    for {set bit 0} {$bit < 7} {incr bit} {
        set source [get_pins -of_objects $gt -filter \
            "REF_PIN_NAME == TXSEQUENCE\[$bit\]"]
        attach_probe_bit [expr {70 + $lane * 7 + $bit}] $source
    }
    incr lane
}

route_design -preserve
set output_dcp [file join $script_dir build uart_gt_txdata_probe.dcp]
set output_bit [file join $script_dir uart_gt_txdata_probe.bit]
write_checkpoint -force $output_dcp
write_bitstream -force $output_bit
puts "FPGA_ARTIFACT=$output_bit"
