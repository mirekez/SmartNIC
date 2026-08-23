set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set generated_dir [file join $repo_dir build rtl processing \
    generated_descriptor_fetcher]
set report_dir [file normalize [file join $script_dir build \
    descriptor_fetcher_check]]
set part xc7k325tffg676-3

file mkdir $report_dir
create_project -in_memory -part $part
read_verilog -sv [list \
    [file join $generated_dir Predef_pkg.sv] \
    [file join $generated_dir DescriptorFetcher_Register_pkg.sv] \
    [file join $generated_dir DescriptorFetcher.sv]]
synth_design -top DescriptorFetcher -part $part -mode out_of_context \
    -flatten_hierarchy rebuilt -resource_sharing auto
create_clock -name clk -period 6.400 [get_ports clk]
report_utilization -hierarchical \
    -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
