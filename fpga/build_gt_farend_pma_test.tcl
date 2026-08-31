# Generate a post-route diagnostic image with GTX far-end PMA loopback
# (LOOPBACK=3'b100) on both Ethernet channels.  In this mode each external
# receiver is connected inside the GTX directly to its transmitter, so the
# attached PC should receive its own serial stream back.  This distinguishes
# a physical GTX/SFP transmit-path failure from malformed local PCS output.
set script_dir [file dirname [file normalize [info script]]]
set source_dcp [file join $script_dir build xgmii_idle.dcp]
if {![file exists $source_dcp]} {
    error "Missing forced-idle checkpoint: $source_dcp"
}

proc ethernet_gt_cells {} {
    set cells [get_cells -hierarchical -filter {
        REF_NAME == GTXE2_CHANNEL && (NAME =~ eth0/* || NAME =~ eth1/*)}]
    if {[llength $cells] != 2} {
        error "Expected two Ethernet GTX cells, found [llength $cells]"
    }
    return $cells
}

proc tie_pins_high {pins prefix} {
    if {[llength $pins] == 0} {
        error "No pins supplied for $prefix"
    }
    foreach pin $pins {
        set old_net [get_nets -quiet -of_objects $pin]
        if {[llength $old_net] != 1} {
            error "Expected one existing net on $pin, found [llength $old_net]"
        }
        disconnect_net -net $old_net -objects $pin
    }
    create_cell -reference VCC ${prefix}_source
    create_net ${prefix}_net
    connect_net -net ${prefix}_net -objects [get_pins ${prefix}_source/P]
    connect_net -hierarchical -net ${prefix}_net -objects $pins
}

open_checkpoint $source_dcp
set loopback_bit2 {}
foreach gt [ethernet_gt_cells] {
    set pin [get_pins -quiet -of_objects $gt -filter {
        REF_PIN_NAME == "LOOPBACK[2]"}]
    if {[llength $pin] != 1} {
        error "Expected one LOOPBACK\[2\] pin on $gt, found [llength $pin]"
    }
    lappend loopback_bit2 $pin
}
tie_pins_high $loopback_bit2 farend_pma
puts "FAREND_PMA_PINS=[llength $loopback_bit2]"

# LOOPBACK[1:0] retain their routed zero values, producing 3'b100.  The
# source checkpoint also keeps both board TX_EN outputs asserted.
route_design -preserve
report_route_status -file [file join $script_dir build farend_pma_route_status.rpt]
report_drc -file [file join $script_dir build farend_pma_drc.rpt]
write_checkpoint -force [file join $script_dir build farend_pma.dcp]
set artifact [file join $script_dir open_switch_xgmii_idle_farend_pma.bit]
write_bitstream -force $artifact
puts "FPGA_ARTIFACT=$artifact"
