# Isolated QoR check for the CppHDL-generated InputBalancer hierarchy. This
# catches accidental LUTRAM/register expansion before a whole-SmartNIC run
# spends hours elaborating the design.
set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set report_dir [file normalize [file join $script_dir build input_balancer_check]]
set generated_dir [file join $repo_dir rtl generated]
set part xc7k325tffg676-3

file mkdir $report_dir
create_project -in_memory -part $part
set_property target_language Verilog [current_project]
read_verilog -sv [list \
    [file join $generated_dir Predef_pkg.sv] \
    [file join $generated_dir SmartNicMemory.sv] \
    [file join $generated_dir Fifo.sv] \
    [file join $generated_dir InputBalancer.sv]]

set started [clock milliseconds]
synth_design -top InputBalancer -part $part -mode out_of_context \
    -flatten_hierarchy rebuilt -resource_sharing auto
set elapsed [expr {([clock milliseconds] - $started) / 1000.0}]

create_clock -name net_clk -period 6.400 [get_ports net_clk]
report_utilization -hierarchical -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
report_design_analysis -logic_level_distribution \
    -file [file join $report_dir design_analysis.rpt]
write_checkpoint -force [file join $report_dir InputBalancer_synth.dcp]

puts [format "INPUT_BALANCER_SYNTH_SECONDS %.3f" $elapsed]
puts "INPUT_BALANCER_REPORT_DIR $report_dir"
