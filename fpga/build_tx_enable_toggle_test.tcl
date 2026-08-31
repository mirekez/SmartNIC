# Generate a forced-XGMII-idle diagnostic image whose two board TX_EN outputs
# toggle from UARTProbe's free-running timestamp counter bit 29.  With the
# 156.25 MHz net clock this remains in each state for about 3.44 seconds,
# making remote-module received optical power easy to correlate without
# unplugging fibers.
set script_dir [file dirname [file normalize [info script]]]
set source_dcp [file join $script_dir build xgmii_idle.dcp]
if {![file exists $source_dcp]} {
    error "Missing forced-idle checkpoint: $source_dcp"
}

open_checkpoint $source_dcp
set timestamp_q_candidates [get_pins -quiet -hierarchical -filter {
    REF_PIN_NAME == Q && NAME =~ *timestamp_reg*}]
set toggle_pin {}
foreach pin $timestamp_q_candidates {
    if {[regexp {timestamp_reg(_reg)?\[29\]/Q$} $pin]} {
        lappend toggle_pin $pin
    }
}
if {[llength $toggle_pin] != 1} {
    puts "TIMESTAMP_Q_CANDIDATES=$timestamp_q_candidates"
    error "Expected timestamp_reg\[29\]/Q, found [llength $toggle_pin]"
}
set toggle_net [get_nets -quiet -of_objects $toggle_pin]
if {[llength $toggle_net] != 1} {
    error "Expected one timestamp toggle net, found [llength $toggle_net]"
}

set tx_enable_inputs [get_pins -quiet -hierarchical -filter {
    NAME =~ sfp_tx_en_OBUF*_inst/I}]
if {[llength $tx_enable_inputs] != 2} {
    error "Expected two SFP TX_EN OBUF inputs, found [llength $tx_enable_inputs]"
}
foreach pin $tx_enable_inputs {
    disconnect_net -net [get_nets -of_objects $pin] -objects $pin
}
connect_net -hierarchical -net $toggle_net -objects $tx_enable_inputs
puts "TX_ENABLE_TOGGLE_SOURCE=$toggle_pin"
puts "TX_ENABLE_TOGGLE_LOADS=[llength $tx_enable_inputs]"

route_design -preserve
report_route_status -file [file join $script_dir build txenable_toggle_route_status.rpt]
report_drc -file [file join $script_dir build txenable_toggle_drc.rpt]
write_checkpoint -force [file join $script_dir build txenable_toggle.dcp]
set artifact [file join $script_dir open_switch_xgmii_idle_txenable_toggle.bit]
write_bitstream -force $artifact
puts "FPGA_ARTIFACT=$artifact"
