# Generate a diagnostic image from the fully implemented main design with the
# XGMII transmit inputs of both 10G PCS instances forced to legal Ethernet
# idle characters.  This bypasses only the MAC transmit outputs; the normal
# clocking, resets, PCS/GTX configuration, polarity, and board TX enables are
# retained.
set script_dir [file dirname [file normalize [info script]]]
set source_dcp [file join $script_dir build open_switch.runs impl_1 \
    klusterlab_top_postroute_physopt.dcp]
if {![file exists $source_dcp]} {
    error "Missing implemented checkpoint: $source_dcp"
}

open_checkpoint $source_dcp

# Select only the boundary pins on the two PCS wrappers.  Deeper generated-IP
# pins deliberately do not match these paths.
set pcs_txc [get_pins -hierarchical -filter {
    DIRECTION == IN &&
    (NAME =~ eth0/inst/xpcs/xgmii_txc* ||
     NAME =~ eth1/inst/xpcs/xgmii_txc*)}]
set pcs_txd [get_pins -hierarchical -filter {
    DIRECTION == IN &&
    (NAME =~ eth0/inst/xpcs/xgmii_txd* ||
     NAME =~ eth1/inst/xpcs/xgmii_txd*)}]
if {[llength $pcs_txc] != 16} {
    error "Expected 16 PCS XGMII TXC pins, found [llength $pcs_txc]"
}
if {[llength $pcs_txd] != 128} {
    error "Expected 128 PCS XGMII TXD pins, found [llength $pcs_txd]"
}

foreach pin [concat $pcs_txc $pcs_txd] {
    set old_net [get_nets -quiet -of_objects $pin]
    if {[llength $old_net] != 1} {
        error "Expected one existing net on $pin, found [llength $old_net]"
    }
    disconnect_net -net $old_net -objects $pin
}

create_cell -reference VCC xgmii_idle_vcc
create_net xgmii_idle_vcc_net
connect_net -net xgmii_idle_vcc_net -objects [get_pins xgmii_idle_vcc/P]
create_cell -reference GND xgmii_idle_gnd
create_net xgmii_idle_gnd_net
connect_net -net xgmii_idle_gnd_net -objects [get_pins xgmii_idle_gnd/G]

# XGMII idle is eight control characters per 64-bit word:
#   TXC = 8'hff, TXD = 64'h0707070707070707.
connect_net -hierarchical -net xgmii_idle_vcc_net -objects $pcs_txc
set txd_high {}
set txd_low {}
foreach pin $pcs_txd {
    if {![regexp {\[([0-9]+)\]$} $pin unused bit_index]} {
        error "Cannot extract XGMII TXD bit index from $pin"
    }
    if {($bit_index % 8) < 3} {
        lappend txd_high $pin
    } else {
        lappend txd_low $pin
    }
}
if {[llength $txd_high] != 48 || [llength $txd_low] != 80} {
    error "Bad idle partition: high=[llength $txd_high], low=[llength $txd_low]"
}
connect_net -hierarchical -net xgmii_idle_vcc_net -objects $txd_high
connect_net -hierarchical -net xgmii_idle_gnd_net -objects $txd_low

puts "XGMII_IDLE_TXC_HIGH=[llength $pcs_txc]"
puts "XGMII_IDLE_TXD_HIGH=[llength $txd_high]"
puts "XGMII_IDLE_TXD_LOW=[llength $txd_low]"
foreach pin [lsort $pcs_txc] {
    puts "XGMII_IDLE_PIN=$pin NET=[get_nets -of_objects $pin]"
}

route_design -preserve
report_route_status -file [file join $script_dir build xgmii_idle_route_status.rpt]
report_drc -file [file join $script_dir build xgmii_idle_drc.rpt]
report_timing_summary -file [file join $script_dir build xgmii_idle_timing.rpt]
write_checkpoint -force [file join $script_dir build xgmii_idle.dcp]
write_bitstream -force [file join $script_dir open_switch_xgmii_idle.bit]
puts "FPGA_ARTIFACT=[file join $script_dir open_switch_xgmii_idle.bit]"
