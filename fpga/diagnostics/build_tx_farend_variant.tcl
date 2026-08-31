# Post-route FPGA-TX isolation image.  It loops each received serial stream
# back through the corresponding GTX transmitter, forces both electrical and
# module TX disables inactive, and permits static polarity/emphasis sweeps.
set script_dir [file normalize [file dirname [info script]]]
set source_dcp [file join $script_dir build uart_10g_probe \
    uart_10g_probe.runs impl_1 uart_10g_probe_top_routed.dcp]

proc env_int {name default maximum} {
    set value $default
    if {[info exists ::env($name)]} { set value $::env($name) }
    if {![string is integer -strict $value] || $value < 0 || $value > $maximum} {
        error "$name must be 0..$maximum"
    }
    return $value
}

proc force_pin {pin value stem} {
    set old_net [get_nets -quiet -of_objects $pin]
    if {[llength $old_net] == 1} {
        disconnect_net -net $old_net -objects $pin
    }
    set cell ${stem}_source
    set net ${stem}_net
    if {[llength [get_cells -quiet $cell]] == 0} {
        if {$value} { set ref VCC; set refpin P } else { set ref GND; set refpin G }
        create_cell -reference $ref $cell
        create_net $net
        connect_net -net $net -objects [get_pins $cell/$refpin]
    }
    connect_net -hierarchical -net $net -objects $pin
}

set polarity [env_int GT_TX_POLARITY 0 3]
set tx_pre [env_int GT_TX_PRE 0 31]
set tx_post [env_int GT_TX_POST 12 31]
set tx_diff [env_int GT_TX_DIFF 15 15]
set farend [env_int GT_TX_FAREND 1 1]
set mode [expr {$farend ? "farend" : "normal"}]
set stem [format "uart_tx_%s_pol%d_pre%02d_post%02d_diff%02d" \
    $mode $polarity $tx_pre $tx_post $tx_diff]

open_checkpoint $source_dcp
set gts [lsort [get_cells -hierarchical -filter {REF_NAME == GTXE2_CHANNEL}]]
if {[llength $gts] != 2} { error "Expected two Ethernet GTX channels" }
set lane 0
foreach gt $gts {
    force_pin [get_pins -of_objects $gt -filter {REF_PIN_NAME == TXINHIBIT}] 0 ${stem}_inhibit_${lane}
    force_pin [get_pins -of_objects $gt -filter {REF_PIN_NAME == LOOPBACK[2]}] $farend ${stem}_farend_${lane}
    force_pin [get_pins -of_objects $gt -filter {REF_PIN_NAME == LOOPBACK[1]}] 0 ${stem}_loop1_${lane}
    force_pin [get_pins -of_objects $gt -filter {REF_PIN_NAME == LOOPBACK[0]}] 0 ${stem}_loop0_${lane}
    force_pin [get_pins -of_objects $gt -filter {REF_PIN_NAME == TXPOLARITY}] \
        [expr {($polarity >> $lane) & 1}] ${stem}_polarity_${lane}
    foreach {port width value} [list TXPRECURSOR 5 $tx_pre \
            TXPOSTCURSOR 5 $tx_post TXDIFFCTRL 4 $tx_diff] {
        for {set bit 0} {$bit < $width} {incr bit} {
            force_pin [get_pins -of_objects $gt -filter \
                "REF_PIN_NAME == ${port}\[$bit\]"] \
                [expr {($value >> $bit) & 1}] ${stem}_${port}_${lane}_${bit}
        }
    }
    incr lane
}
set lane 0
foreach pin [lsort [get_pins -quiet -hierarchical -filter \
        {NAME =~ sfp_tx_en_OBUF*_inst/I}]] {
    force_pin $pin 1 ${stem}_module_enable_${lane}
    incr lane
}
route_design -preserve
write_checkpoint -force [file join $script_dir build ${stem}.dcp]
write_bitstream -force [file join $script_dir ${stem}.bit]
puts "FPGA_ARTIFACT=[file join $script_dir ${stem}.bit]"
