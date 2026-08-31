# Generate three post-route 10G transmit diagnostics from the forced-XGMII-
# idle checkpoint:
#   1. maximum GTX output swing (TXDIFFCTRL 4'b1111),
#   2. opposite board TX_EN level, and
#   3. GTX near-end PMA loopback (LOOPBACK 3'b010).
# These are bring-up experiments and are not normal project outputs.
set script_dir [file dirname [file normalize [info script]]]
set source_dcp [file join $script_dir build xgmii_idle.dcp]
if {![file exists $source_dcp]} {
    error "Missing forced-idle checkpoint: $source_dcp"
}
set requested_variant all
if {[info exists ::env(GT_TX_TEST)]} {
    set requested_variant $::env(GT_TX_TEST)
}
if {$requested_variant ni {all maxswing txenable_low nearend_pma}} {
    error "GT_TX_TEST must be all, maxswing, txenable_low, or nearend_pma"
}

proc ethernet_gt_cells {} {
    set cells [get_cells -hierarchical -filter {
        REF_NAME == GTXE2_CHANNEL && (NAME =~ eth0/* || NAME =~ eth1/*)}]
    if {[llength $cells] != 2} {
        error "Expected two Ethernet GTX cells, found [llength $cells]"
    }
    return $cells
}

proc tie_pins {pins value prefix} {
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
    if {$value} {
        create_cell -reference VCC ${prefix}_source
        set source_pin [get_pins ${prefix}_source/P]
    } else {
        create_cell -reference GND ${prefix}_source
        set source_pin [get_pins ${prefix}_source/G]
    }
    create_net ${prefix}_net
    connect_net -net ${prefix}_net -objects $source_pin
    connect_net -hierarchical -net ${prefix}_net -objects $pins
}

proc finish_variant {script_dir stem} {
    route_design -preserve
    report_route_status -file [file join $script_dir build ${stem}_route_status.rpt]
    report_drc -file [file join $script_dir build ${stem}_drc.rpt]
    write_checkpoint -force [file join $script_dir build ${stem}.dcp]
    set artifact [file join $script_dir ${stem}.bit]
    write_bitstream -force $artifact
    puts "FPGA_ARTIFACT=$artifact"
    close_design
}

# The generated core normally uses 4'b1110.  Raise bit zero to select the
# maximum available GTX differential output swing.
if {$requested_variant in {all maxswing}} {
    open_checkpoint $source_dcp
    set swing_lsb {}
    foreach gt [ethernet_gt_cells] {
        set pin [get_pins -quiet -of_objects $gt -filter {
            REF_PIN_NAME == "TXDIFFCTRL[0]"}]
        if {[llength $pin] != 1} {
            error "Expected one TXDIFFCTRL\[0\] pin on $gt, found [llength $pin]"
        }
        lappend swing_lsb $pin
    }
    tie_pins $swing_lsb 1 maxswing
    puts "MAXSWING_PINS=[llength $swing_lsb]"
    finish_variant $script_dir open_switch_xgmii_idle_maxswing
}

# The schematic says TX_EN=1 turns on the N-MOSFET and pulls SFP TX_DISABLE
# low.  This opposite-level image tests that board interpretation explicitly.
if {$requested_variant in {all txenable_low}} {
    open_checkpoint $source_dcp
    set tx_enable_inputs [get_pins -quiet -hierarchical -filter {
        NAME =~ sfp_tx_en_OBUF*_inst/I}]
    if {[llength $tx_enable_inputs] != 2} {
        error "Expected two SFP TX_EN OBUF inputs, found [llength $tx_enable_inputs]"
    }
    tie_pins $tx_enable_inputs 0 txenable_low
    puts "TXENABLE_LOW_PINS=[llength $tx_enable_inputs]"
    finish_variant $script_dir open_switch_xgmii_idle_txenable_low
}

# 3'b010 is near-end PMA loopback for 7-series GTX.  Because this mode is
# static before the design reset releases, the normal startup reset sequence
# also initializes the receiver after entering loopback.
if {$requested_variant in {all nearend_pma}} {
    open_checkpoint $source_dcp
    set loopback_bit1 {}
    foreach gt [ethernet_gt_cells] {
        set pin [get_pins -quiet -of_objects $gt -filter {
            REF_PIN_NAME == "LOOPBACK[1]"}]
        if {[llength $pin] != 1} {
            error "Expected one LOOPBACK\[1\] pin on $gt, found [llength $pin]"
        }
        lappend loopback_bit1 $pin
    }
    tie_pins $loopback_bit1 1 nearend_pma

    # Keep PCS signal detection asserted so this image can be tested with both
    # receive fibers physically disconnected.
    set signal_detect_pins [get_pins -quiet -hierarchical -filter {
        DIRECTION == IN &&
        (NAME == eth0/inst/xpcs/signal_detect ||
         NAME == eth1/inst/xpcs/signal_detect)}]
    if {[llength $signal_detect_pins] != 2} {
        error "Expected two PCS signal_detect pins, found [llength $signal_detect_pins]"
    }
    tie_pins $signal_detect_pins 1 nearend_signal_detect
    puts "NEAREND_PMA_PINS=[llength $loopback_bit1]"
    puts "NEAREND_SIGNAL_DETECT_PINS=[llength $signal_detect_pins]"
    finish_variant $script_dir open_switch_xgmii_idle_nearend_pma
}
