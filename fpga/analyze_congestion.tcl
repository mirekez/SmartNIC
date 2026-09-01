# Analyze the preserved CPU-loopback routed checkpoint without modifying it.
set script_dir [file normalize [file dirname [info script]]]
set checkpoint [lindex $argv 0]
if {$checkpoint eq ""} {
    set checkpoint [file join $script_dir build klusterlab_top_cpu_release_fix_congested_routed.dcp]
}
set output_dir [lindex $argv 1]
if {$output_dir eq ""} {
    set output_dir [file join $script_dir congestion_analysis]
}
file mkdir $output_dir

open_checkpoint $checkpoint

report_design_analysis -congestion -min_congestion_level 3 \
    -file [file join $output_dir congestion.rpt]
report_design_analysis -complexity -hierarchical_depth 12 \
    -file [file join $output_dir complexity.rpt]
report_utilization -hierarchical -hierarchical_depth 12 \
    -hierarchical_percentages \
    -file [file join $output_dir hierarchical_utilization.rpt]
report_high_fanout_nets -timing -load_types -max_nets 200 \
    -file [file join $output_dir high_fanout_loads.rpt]
report_high_fanout_nets -timing -clock_regions -max_nets 200 \
    -file [file join $output_dir high_fanout_regions.rpt]
report_timing -setup -max_paths 300 -nworst 1 -sort_by group \
    -path_type full_clock_expanded -routable_nets \
    -file [file join $output_dir worst_300_setup.rpt]

# Route reported the common hotspot in INT tile coordinates. Export every
# placed primitive in the union so hierarchy ownership can be counted outside
# Vivado without approximating from SLICE/BRAM/DSP coordinates.
set hotspot_tiles {}
for {set x 16} {$x <= 63} {incr x} {
    for {set y 94} {$y <= 141} {incr y} {
        foreach side {L R} {
            set tile [get_tiles -quiet INT_${side}_X${x}Y${y}]
            if {[llength $tile]} {
                lappend hotspot_tiles {*}$tile
            }
        }
    }
}
set hotspot_sites [get_sites -quiet -of_objects $hotspot_tiles]
set hotspot_cells [get_cells -quiet -of_objects $hotspot_sites]
set output [open [file join $output_dir hotspot_cells.tsv] w]
puts $output "ref_name\tloc\tclock_region\tcell"
foreach cell $hotspot_cells {
    set site [get_sites -quiet -of_objects $cell]
    set clock_region [get_clock_regions -quiet -of_objects $site]
    puts $output "[get_property REF_NAME $cell]\t[get_property LOC $cell]\t$clock_region\t$cell"
}
close $output
puts "HOTSPOT_TILES=[llength $hotspot_tiles]"
puts "HOTSPOT_SITES=[llength $hotspot_sites]"
puts "HOTSPOT_CELLS=[llength $hotspot_cells]"

close_design
exit
