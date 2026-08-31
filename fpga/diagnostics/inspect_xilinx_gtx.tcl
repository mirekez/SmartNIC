set script_dir [file normalize [file dirname [info script]]]
set source_dcp [file join $script_dir build uart_10g_probe \
    uart_10g_probe.runs impl_1 uart_10g_probe_top_routed.dcp]

open_checkpoint $source_dcp
foreach gt [lsort [get_cells -hierarchical -filter {REF_NAME == GTXE2_CHANNEL}]] {
    puts "GTX_CELL=$gt LOC=[get_property LOC $gt]"
    foreach pin_name {TXINHIBIT TXP TXN} {
        set pin [get_pins -quiet $gt/$pin_name]
        puts "  PIN=$pin_name NET=[get_nets -quiet -of_objects $pin]"
    }
}
close_design
exit
