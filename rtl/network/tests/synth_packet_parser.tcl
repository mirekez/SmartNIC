# Vivado out-of-context synthesis for generated CppHDL PacketParser RTL.
# Usage: vivado -mode batch -source synth_packet_parser.tcl -tclargs \
#        <generated-dir> <lane-width> <report-dir> ?part? ?synth|route?

if {$argc < 3} {
    error "expected generated-dir, lane-width, and report-dir"
}

set generated_dir [file normalize [lindex $argv 0]]
set lane_width [lindex $argv 1]
set report_dir [file normalize [lindex $argv 2]]
# The local Vivado installation contains the Alveo U250 (Virtex UltraScale+).
set part_name "xcu250-figd2104-2L-e"
if {$argc >= 4} {
    set part_name [lindex $argv 3]
}
set flow_mode "synth"
if {$argc >= 5} {
    set flow_mode [lindex $argv 4]
}
if {$lane_width != 160 && $lane_width != 320} {
    error "lane-width must be 160 or 320"
}
if {$flow_mode != "synth" && $flow_mode != "route"} {
    error "flow mode must be synth or route"
}

file mkdir $report_dir
set rtl_files [list \
    Predef_pkg.sv \
    PacketParserFields_pkg.sv \
    PacketParserWord_pkg.sv \
    PacketParserProgress_pkg.sv \
    PacketParserPipeWord_pkg.sv \
    PacketParserHeaderId_pkg.sv \
    PacketParserCall_pkg.sv \
    PacketParserFlags_pkg.sv \
    PacketParser.sv]
foreach rtl_file $rtl_files {
    set rtl_path [file join $generated_dir $rtl_file]
    if {![file exists $rtl_path]} {
        error "missing generated RTL: $rtl_path"
    }
    read_verilog -sv $rtl_path
}

# Read the clock constraint before synthesis so synthesis is timing-driven.
set script_dir [file dirname [file normalize [info script]]]
read_xdc [file join $script_dir packet_parser_3p2ns.xdc]
synth_design -top PacketParser -part $part_name -mode out_of_context \
    -generic LANE_WIDTH=$lane_width -flatten_hierarchy rebuilt

report_utilization -hierarchical -file \
    [file join $report_dir utilization_hierarchical.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_summary.rpt]
report_design_analysis -logic_level_distribution \
    -file [file join $report_dir logic_levels.rpt]
report_high_fanout_nets -timing -load_types -max_nets 50 \
    -file [file join $report_dir high_fanout.rpt]
write_checkpoint -force [file join $report_dir packet_parser_synth.dcp]

if {$flow_mode == "route"} {
    opt_design
    place_design
    phys_opt_design
    route_design
    report_utilization -hierarchical -file \
        [file join $report_dir utilization_post_route_hierarchical.rpt]
    report_utilization -file \
        [file join $report_dir utilization_post_route.rpt]
    report_timing_summary -delay_type max -max_paths 20 \
        -report_unconstrained \
        -file [file join $report_dir timing_post_route.rpt]
    report_timing_summary -delay_type min_max -max_paths 20 \
        -file [file join $report_dir timing_min_max_post_route.rpt]
    report_design_analysis -logic_level_distribution \
        -file [file join $report_dir logic_levels_post_route.rpt]
    report_design_analysis -congestion \
        -file [file join $report_dir congestion_post_route.rpt]
    report_high_fanout_nets -timing -load_types -max_nets 50 \
        -file [file join $report_dir high_fanout_post_route.rpt]
    write_checkpoint -force [file join $report_dir packet_parser_route.dcp]
}

set utilization [report_utilization -return_string]
set timing [report_timing_summary -delay_type max -max_paths 1 -return_string]
puts "PACKET_PARSER_SYNTHESIS width=$lane_width part=$part_name mode=$flow_mode"
puts $utilization
puts $timing
