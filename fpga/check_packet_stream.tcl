set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set report_dir [file normalize [file join $script_dir build packet_stream_check]]
set generated_dir [file join $repo_dir rtl generated]
set part xc7k160tffg676-3

file mkdir $report_dir
foreach direction {{64 256 up} {256 64 down}} {
    lassign $direction source_width destination_width name
    create_project -in_memory -part $part
    read_verilog -sv [list \
        [file join $generated_dir Predef_pkg.sv] \
        [file join $generated_dir PacketStream.sv]]
    synth_design -top PacketStream -part $part -mode out_of_context \
        -generic SRC_WIDTH=$source_width -generic DST_WIDTH=$destination_width \
        -flatten_hierarchy rebuilt
    create_clock -name net_clk -period 6.400 [get_ports net_clk]
    report_utilization -hierarchical \
        -file [file join $report_dir utilization_$name.rpt]
    report_timing_summary -delay_type max -max_paths 20 \
        -file [file join $report_dir timing_$name.rpt]
    close_project
}
