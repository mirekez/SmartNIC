# Generate a diagnostic image from the fully implemented main design with
# TXPOLARITY asserted only on the two Ethernet GTX channels.  RX polarity and
# the PCIe GTX are intentionally unchanged.  This is a bring-up experiment,
# not the normal project build output.
set script_dir [file dirname [file normalize [info script]]]
set source_dcp [file join $script_dir build open_switch.runs impl_1 \
    klusterlab_top_postroute_physopt.dcp]
if {![file exists $source_dcp]} {
    error "Missing implemented checkpoint: $source_dcp"
}

open_checkpoint $source_dcp
set ethernet_txpolarity [get_pins -hierarchical -filter {
    REF_PIN_NAME == TXPOLARITY && (NAME =~ eth0/* || NAME =~ eth1/*)}]
if {[llength $ethernet_txpolarity] != 2} {
    error "Expected two Ethernet TXPOLARITY pins, found [llength $ethernet_txpolarity]"
}

foreach pin $ethernet_txpolarity {
    disconnect_net -net [get_nets -of_objects $pin] -objects $pin
}
create_cell -reference VCC ethernet_txpolarity_vcc
create_net ethernet_txpolarity_vcc_net
connect_net -net ethernet_txpolarity_vcc_net \
    -objects [get_pins ethernet_txpolarity_vcc/P]
connect_net -hierarchical -net ethernet_txpolarity_vcc_net \
    -objects $ethernet_txpolarity
foreach pin $ethernet_txpolarity {
    puts "TXPOLARITY_INVERTED=$pin NET=[get_nets -of_objects $pin]"
}

route_design -preserve
report_route_status -file [file join $script_dir build txpolarity_route_status.rpt]
report_drc -file [file join $script_dir build txpolarity_drc.rpt]
report_timing_summary -file [file join $script_dir build txpolarity_timing.rpt]
write_checkpoint -force [file join $script_dir build txpolarity_inverted.dcp]
write_bitstream -force [file join $script_dir open_switch_txpolarity_inverted.bit]
puts "FPGA_ARTIFACT=[file join $script_dir open_switch_txpolarity_inverted.bit]"
