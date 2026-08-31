# Generate one post-route 10G transmit-equalization diagnostic from the
# forced-XGMII-idle checkpoint.  Select tap coefficients through environment
# variables, for example:
#   GT_TX_PRE=0 GT_TX_POST=12 GT_TX_DIFF=15 vivado ...
set script_dir [file dirname [file normalize [info script]]]
set source_dcp [file join $script_dir build xgmii_idle.dcp]
if {![file exists $source_dcp]} {
    error "Missing forced-idle checkpoint: $source_dcp"
}

proc env_integer {name default maximum} {
    set value $default
    if {[info exists ::env($name)]} {
        set value $::env($name)
    }
    if {![string is integer -strict $value] || $value < 0 || $value > $maximum} {
        error "$name must be an integer from 0 through $maximum"
    }
    return $value
}

proc ethernet_gt_cells {} {
    set cells [get_cells -hierarchical -filter {
        REF_NAME == GTXE2_CHANNEL && (NAME =~ eth0/* || NAME =~ eth1/*)}]
    if {[llength $cells] != 2} {
        error "Expected two Ethernet GTX cells, found [llength $cells]"
    }
    return $cells
}

proc set_gt_vector {gts port width value prefix} {
    for {set bit 0} {$bit < $width} {incr bit} {
        set pins {}
        foreach gt $gts {
            set pin [get_pins -quiet -of_objects $gt -filter \
                "REF_PIN_NAME == \"${port}\[$bit\]\""]
            if {[llength $pin] != 1} {
                error "Expected one ${port}\[$bit\] pin on $gt, found [llength $pin]"
            }
            lappend pins $pin
        }
        foreach pin $pins {
            set old_net [get_nets -quiet -of_objects $pin]
            if {[llength $old_net] != 1} {
                error "Expected one old net on $pin, found [llength $old_net]"
            }
            disconnect_net -net $old_net -objects $pin
        }
        if {$value & (1 << $bit)} {
            set primitive VCC
            set source_pin P
        } else {
            set primitive GND
            set source_pin G
        }
        create_cell -reference $primitive ${prefix}_${port}_${bit}_source
        create_net ${prefix}_${port}_${bit}_net
        connect_net -net ${prefix}_${port}_${bit}_net -objects \
            [get_pins ${prefix}_${port}_${bit}_source/$source_pin]
        connect_net -hierarchical -net ${prefix}_${port}_${bit}_net -objects $pins
    }
}

set tx_pre  [env_integer GT_TX_PRE 0 31]
set tx_post [env_integer GT_TX_POST 12 31]
set tx_diff [env_integer GT_TX_DIFF 15 15]
# With automatic main-cursor selection, the two tap coefficients consume an
# 80-unit driver budget.  The tested range stays well inside that budget.
if {$tx_pre + $tx_post > 40} {
    error "Conservative test limit requires GT_TX_PRE + GT_TX_POST <= 40"
}
set stem [format "open_switch_xgmii_idle_pre%02d_post%02d_diff%02d" \
    $tx_pre $tx_post $tx_diff]

open_checkpoint $source_dcp
set gts [ethernet_gt_cells]
set_gt_vector $gts TXPRECURSOR 5 $tx_pre emphasis
set_gt_vector $gts TXPOSTCURSOR 5 $tx_post emphasis
set_gt_vector $gts TXDIFFCTRL 4 $tx_diff emphasis
puts "GT_TX_PRE=$tx_pre GT_TX_POST=$tx_post GT_TX_DIFF=$tx_diff"

route_design -preserve
report_route_status -file [file join $script_dir build ${stem}_route_status.rpt]
report_drc -file [file join $script_dir build ${stem}_drc.rpt]
write_checkpoint -force [file join $script_dir build ${stem}.dcp]
set artifact [file join $script_dir ${stem}.bit]
write_bitstream -force $artifact
puts "FPGA_ARTIFACT=$artifact"
