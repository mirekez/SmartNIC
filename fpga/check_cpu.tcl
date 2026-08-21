# Isolated QoR check for the four-core CppHDL CPU hierarchy.
set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set report_dir [file normalize [file join $script_dir build cpu_check]]
set generated_dir [file join $repo_dir build rtl processing generated_cpu]
set part xc7k325tffg676-3

file mkdir $report_dir
create_project -in_memory -part $part
set_property target_language Verilog [current_project]
add_files -norecurse [glob -directory $generated_dir *.sv]
set_property top CPU [current_fileset]
update_compile_order -fileset sources_1

set flatten_mode rebuilt
if {$argc > 0} {
    set flatten_mode [lindex $argv 0]
}
set synth_directive Default
if {$argc > 1} {
    set synth_directive [lindex $argv 1]
}
set started [clock milliseconds]
synth_design -top CPU -part $part -mode out_of_context \
    -flatten_hierarchy $flatten_mode -resource_sharing auto \
    -directive $synth_directive
set elapsed [expr {([clock milliseconds] - $started) / 1000.0}]

create_clock -name cpu_clk -period 3.200 [get_ports clk]
create_clock -name l2_clk -period 6.400 [get_ports l2_clock]
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
write_checkpoint -force [file join $report_dir CPU_synth.dcp]

puts [format "CPU_SYNTH_SECONDS %.3f" $elapsed]
puts "CPU_REPORT_DIR $report_dir"
