set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set generated_dir [file join $repo_dir rtl generated]
set report_dir [file join $script_dir build file_storage_check]
file mkdir $report_dir

create_project -in_memory -part xc7k160tffg676-3
read_verilog -sv [list \
    [file join $generated_dir Predef_pkg.sv] \
    [file join $generated_dir FileStorage.sv] \
    [file join $generated_dir File.sv]]
synth_design -top File -part xc7k160tffg676-3 -mode out_of_context \
    -directive AreaOptimized_high -resource_sharing on
create_clock -name clk -period 6.400 [get_ports clk]
report_utilization -hierarchical \
    -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 \
    -file [file join $report_dir timing_summary.rpt]
