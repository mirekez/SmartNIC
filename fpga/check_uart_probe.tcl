set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set output_dir [file join $script_dir uart_probe_check]
file delete -force $output_dir
file mkdir $output_dir

read_verilog -sv [file join $repo_dir rtl generated Predef_pkg.sv]
read_verilog -sv [file join $repo_dir rtl generated UARTProbeMemory.sv]
read_verilog -sv [file join $repo_dir rtl generated UARTProbe.sv]
synth_design -top UARTProbe -part xc7k325tffg676-3 -flatten_hierarchy rebuilt
create_clock -name probe_clk -period 20.000 [get_ports clk]

report_utilization -file [file join $output_dir utilization.rpt]
report_timing_summary -file [file join $output_dir timing.rpt]
write_checkpoint -force [file join $output_dir uart_probe_synth.dcp]

puts "UART_PROBE_BRAM36=[llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]]"
puts "UART_PROBE_BRAM18=[llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]"
puts "UART_PROBE_LUT=[llength [get_cells -hier -filter {REF_NAME =~ LUT*}]]"
puts "UART_PROBE_FF=[llength [get_cells -hier -filter {REF_NAME =~ FD*}]]"
puts "UART_PROBE_CHECKPOINT=[file join $output_dir uart_probe_synth.dcp]"
