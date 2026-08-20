# Isolated QoR check for the CppHDL RxRAM hierarchy. The packet-store control
# remains generated from C++; only SmartNicRAM is a canonical physical RAM leaf.
set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set report_dir [file normalize [file join $script_dir build rx_ram_check]]
set generated_dir [file join $repo_dir rtl generated]
set part xc7k160tffg676-3

file mkdir $report_dir
create_project -in_memory -part $part
set_property target_language Verilog [current_project]
read_verilog -sv [list \
    [file join $generated_dir Predef_pkg.sv] \
    [file join $generated_dir RxRAMWritePair_pkg.sv] \
    [file join $generated_dir SmartNicRAM.sv] \
    [file join $generated_dir RxRAM.sv]]

set started [clock milliseconds]
synth_design -top RxRAM -part $part -mode out_of_context \
    -flatten_hierarchy rebuilt -resource_sharing auto
set elapsed [expr {([clock milliseconds] - $started) / 1000.0}]

create_clock -name net_clk -period 6.400 [get_ports net_clk]
report_utilization -hierarchical -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
write_checkpoint -force [file join $report_dir RxRAM_synth.dcp]

set brams [get_cells -hierarchical \
    -filter {REF_NAME =~ RAMB18* || REF_NAME =~ RAMB36*}]
puts [format "RX_RAM_SYNTH_SECONDS %.3f" $elapsed]
puts "RX_RAM_BRAM_CELLS=[llength $brams]"
puts "RX_RAM_REPORT_DIR $report_dir"
if {[llength $brams] == 0} {
    error "RxRAM packet storage was not mapped to block RAM"
}
