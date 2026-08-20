# Isolated synthesis check for the CppHDL-generated streaming packet parser.
# This intentionally uses the checked-in generated RTL, exactly as the FPGA
# project does, without the rest of the SmartNIC obscuring parser QoR/runtime.
set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set report_dir [file normalize [file join $script_dir build parser_check]]
set generated_dir [file join $repo_dir rtl generated]
if {$argc > 0} {
    set generated_dir [file normalize [lindex $argv 0]]
}
set part xc7k160tffg676-3

file mkdir $report_dir
create_project -in_memory -part $part
set_property target_language Verilog [current_project]

read_verilog -sv [list \
    [file join $generated_dir Predef_pkg.sv] \
    [file join $generated_dir PacketParserFields_pkg.sv] \
    [file join $generated_dir PacketParserWord_pkg.sv] \
    [file join $generated_dir PacketParserProgress_pkg.sv] \
    [file join $generated_dir PacketParserPipeWord_pkg.sv] \
    [file join $generated_dir PacketParserCall_pkg.sv] \
    [file join $generated_dir PacketParserHeaderId_pkg.sv] \
    [file join $generated_dir PacketParserFlags_pkg.sv] \
    [file join $generated_dir SmartNicMemory.sv] \
    [file join $generated_dir PacketParser.sv]]

set synth_directive Default
if {$argc > 1} {
    set synth_directive [lindex $argv 1]
}
set enable_raw 1
if {$argc > 2} {
    set enable_raw [lindex $argv 2]
}
set started [clock milliseconds]
synth_design -top PacketParser -part $part -mode out_of_context \
    -flatten_hierarchy rebuilt -resource_sharing auto \
    -directive $synth_directive -generic ENABLE_RAW=$enable_raw
set elapsed [expr {([clock milliseconds] - $started) / 1000.0}]

# The two ports belong to independent domains in the complete design.  The
# parser's state machine is in net_clk; l2_clk only drains the output FIFO.
# Apply clocks once the in-memory synthesized design has exposed its ports.
create_clock -name net_clk -period 6.400 [get_ports net_clk]
create_clock -name l2_clk  -period 8.000 [get_ports l2_clk]
set_clock_groups -asynchronous \
    -group [get_clocks net_clk] \
    -group [get_clocks l2_clk]

report_utilization -hierarchical -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
report_high_fanout_nets -timing -load_types -max_nets 50 \
    -file [file join $report_dir high_fanout.rpt]
report_design_analysis -logic_level_distribution \
    -file [file join $report_dir design_analysis.rpt]
write_checkpoint -force [file join $report_dir PacketParser_synth.dcp]

puts [format "PACKET_PARSER_SYNTH_SECONDS %.3f" $elapsed]
puts "PACKET_PARSER_REPORT_DIR $report_dir"
