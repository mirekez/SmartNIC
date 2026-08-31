set script_dir [file normalize [file dirname [info script]]]
foreach lane {0 1 2 3} {
    set dcp [file join $script_dir build gt_idle_enable${lane} \
        gt_idle_tx.runs impl_1 gt_idle_tx_top_routed.dcp]
    open_checkpoint $dcp
    puts "ENABLE_TEST=$lane"
    foreach bit {0 1 2 3} {
        set port [get_ports sfp_tx_en\[$bit\]]
        set port_net [get_nets -of_objects $port]
        set obuf [get_cells -of_objects $port_net -filter {REF_NAME == OBUF}]
        set input_net [get_nets -of_objects [get_pins $obuf/I]]
        set driver [get_cells -of_objects $input_net -filter \
            {REF_NAME == VCC || REF_NAME == GND}]
        puts "  bit=$bit pin=[get_property PACKAGE_PIN $port] driver=[get_property REF_NAME $driver]"
    }
    close_design
}
