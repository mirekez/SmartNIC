# Isolated QoR check for the CppHDL FIFO controller and its small physical RAM
# leaf, using the parameters of InputBalancer's per-channel queue.
set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set report_dir [file join $script_dir build fifo_check]
set generated_dir [file join $repo_dir rtl generated]
set part xc7k160tffg676-3

file mkdir $report_dir
create_project -in_memory -part $part
read_verilog -sv [list \
    [file join $generated_dir Predef_pkg.sv] \
    [file join $generated_dir SmartNicMemory.sv] \
    [file join $generated_dir Fifo.sv]]
synth_design -top Fifo -part $part -mode out_of_context \
    -generic FIFO_WIDTH_BYTES=11 -generic FIFO_DEPTH=2048 \
    -generic SHOWAHEAD=1 -generic OUTPUT_REG=1 \
    -flatten_hierarchy rebuilt -directive AreaOptimized_high
create_clock -name net_clk -period 6.400 [get_ports net_clk]
create_clock -name l2_clk -period 6.400 [get_ports l2_clk]
report_utilization -hierarchical -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
write_checkpoint -force [file join $report_dir Fifo_synth.dcp]
