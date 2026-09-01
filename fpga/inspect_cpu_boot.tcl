set script_dir [file normalize [file dirname [info script]]]
set checkpoint [lindex $argv 0]
if {$checkpoint eq ""} {
    set checkpoint [file join $script_dir build open_switch.runs impl_1 klusterlab_top_routed.dcp]
}
open_checkpoint $checkpoint

set sample_tile [lindex [get_tiles -quiet -filter {NAME =~ INT*_X16Y94}] 0]
puts "SAMPLE_TILE=$sample_tile"
if {$sample_tile ne ""} {
    report_property $sample_tile
}

set boot_cells [get_cells -quiet -hier -filter {NAME =~ *boot_memory*}]
puts "BOOT_CELL_COUNT=[llength $boot_cells]"
foreach cell $boot_cells {
    set ref_name [get_property REF_NAME $cell]
    set loc [get_property LOC $cell]
    puts "BOOT_CELL=$cell REF_NAME=$ref_name LOC=$loc"
    if {[string match "RAMB*" $ref_name]} {
        foreach property {INIT_00 INIT_01 INIT_02 INIT_03} {
            puts "  $property=[get_property $property $cell]"
        }
    }
}
close_design
exit
