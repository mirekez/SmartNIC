set script_dir [file normalize [file dirname [info script]]]
set source_dcp [file join $script_dir build uart_10g_probe \
    uart_10g_probe.runs impl_1 uart_10g_probe_top_routed.dcp]

open_checkpoint $source_dcp
create_cell -reference VCC gtx_test_vcc
create_cell -reference GND gtx_test_gnd
create_net gtx_test_vcc_net
create_net gtx_test_gnd_net
connect_net -net gtx_test_vcc_net -objects [get_pins gtx_test_vcc/P]
connect_net -net gtx_test_gnd_net -objects [get_pins gtx_test_gnd/G]

# Keep every optical module enabled.  Isolate the electrical GTX lanes with the
# primitive TXINHIBIT input so the SFP enable circuit cannot confuse the test.
for {set bit 0} {$bit < 4} {incr bit} {
    set port [get_ports sfp_tx_en\[$bit\]]
    set port_net [get_nets -of_objects $port]
    set obuf [get_cells -of_objects $port_net -filter {REF_NAME == OBUF}]
    set input_pin [get_pins $obuf/I]
    set old_net [get_nets -quiet -of_objects $input_pin]
    if {[llength $old_net] == 1} {
        disconnect_net -net $old_net -objects $input_pin
    }
    connect_net -hierarchical -net gtx_test_vcc_net -objects $input_pin
}

set gtx_cells [lsort [get_cells -hierarchical -filter {REF_NAME == GTXE2_CHANNEL}]]
if {[llength $gtx_cells] != 4} {
    error "Expected four GTXE2_CHANNEL cells, got [llength $gtx_cells]"
}

for {set selected 0} {$selected < 4} {incr selected} {
    for {set lane 0} {$lane < 4} {incr lane} {
        set pin [get_pins [lindex $gtx_cells $lane]/TXINHIBIT]
        set old_net [get_nets -quiet -of_objects $pin]
        if {[llength $old_net] == 1} {
            disconnect_net -net $old_net -objects $pin
        }
        if {$lane == $selected} {
            connect_net -hierarchical -net gtx_test_gnd_net -objects $pin
        } else {
            connect_net -hierarchical -net gtx_test_vcc_net -objects $pin
        }
    }
    route_design -preserve
    set output [file join $script_dir xilinx_10g_gtx${selected}.bit]
    write_bitstream -force $output
    puts "XILINX_GTX_ARTIFACT=$output"
}
close_design
exit
