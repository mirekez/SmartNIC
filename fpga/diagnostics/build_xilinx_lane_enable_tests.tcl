set script_dir [file normalize [file dirname [info script]]]
set source_dcp [file join $script_dir build uart_10g_probe \
    uart_10g_probe.runs impl_1 uart_10g_probe_top_routed.dcp]

open_checkpoint $source_dcp
create_cell -reference VCC lane_test_vcc
create_cell -reference GND lane_test_gnd
create_net lane_test_vcc_net
create_net lane_test_gnd_net
connect_net -net lane_test_vcc_net -objects [get_pins lane_test_vcc/P]
connect_net -net lane_test_gnd_net -objects [get_pins lane_test_gnd/G]

for {set selected 0} {$selected < 4} {incr selected} {
    for {set bit 0} {$bit < 4} {incr bit} {
        set port [get_ports sfp_tx_en\[$bit\]]
        set port_net [get_nets -of_objects $port]
        set obuf [get_cells -of_objects $port_net -filter {REF_NAME == OBUF}]
        set input_pin [get_pins $obuf/I]
        set old_net [get_nets -quiet -of_objects $input_pin]
        if {[llength $old_net] == 1} {
            disconnect_net -net $old_net -objects $input_pin
        }
        if {$bit == $selected} {
            connect_net -hierarchical -net lane_test_vcc_net -objects $input_pin
        } else {
            connect_net -hierarchical -net lane_test_gnd_net -objects $input_pin
        }
    }
    route_design -preserve
    set output [file join $script_dir xilinx_10g_enable${selected}.bit]
    write_bitstream -force $output
    puts "XILINX_ENABLE_ARTIFACT=$output"
}
