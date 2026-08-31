set script_dir [file normalize [file dirname [info script]]]
set checkpoint [file join $script_dir build uart_10g_probe \
    uart_10g_probe.runs impl_1 uart_10g_probe_top_routed.dcp]
if {[info exists ::env(DCP)]} {
    set checkpoint [file normalize $::env(DCP)]
}
puts "CHECKPOINT=$checkpoint"
open_checkpoint $checkpoint
foreach gt [get_cells -hierarchical -filter {REF_NAME == GTXE2_CHANNEL}] {
    puts "GT=$gt LOC=[get_property LOC $gt]"
    foreach name {TXRESETDONE TXBUFSTATUS* TXPHALIGNDONE TXPHINITDONE \
                  TXDLYSRESETDONE TXRATEDONE TXOUTCLK TXOUTCLKFABRIC \
                  TXOUTCLKPCS TXPOLARITY TXINHIBIT TXELECIDLE TXPD* \
                  TXDIFFCTRL* TXPRECURSOR* TXPOSTCURSOR* LOOPBACK*} {
        foreach pin [get_pins -quiet -of_objects $gt -filter \
                "REF_PIN_NAME =~ $name"] {
            set pin_net [get_nets -quiet -of_objects $pin]
            puts "  PIN=[get_property REF_PIN_NAME $pin] DIR=[get_property DIRECTION $pin] NET=$pin_net"
            if {[get_property REF_PIN_NAME $pin] eq "TXINHIBIT"} {
                puts "    DRIVERS=[get_pins -quiet -of_objects $pin_net -filter {DIRECTION == OUT}]"
                puts "    ALL_PINS=[get_pins -quiet -of_objects $pin_net] PORTS=[get_ports -quiet -of_objects $pin_net]"
            }
        }
    }
}
