# Non-project Vivado build for the complete generated SmartNIC core.
# Arguments:
#   generated-dir config report-dir part mode jobs bank-depth rx-fifo tx-fifo
#   synthesis-directive

if {$argc != 10} {
    error "Expected: generated-dir 400g|800g report-dir part synth|route jobs bank-depth rx-fifo-depth tx-fifo-words synthesis-directive"
}

set script_dir [file dirname [file normalize [info script]]]
set generated_dir [file normalize [lindex $argv 0]]
set configuration [string tolower [lindex $argv 1]]
set report_dir [file normalize [lindex $argv 2]]
set part_name [lindex $argv 3]
set flow_mode [string tolower [lindex $argv 4]]
set jobs [lindex $argv 5]
set bank_depth [lindex $argv 6]
set rx_fifo_depth [lindex $argv 7]
set tx_fifo_words [lindex $argv 8]
set synthesis_directive [lindex $argv 9]

if {$configuration eq "400g"} {
    set lane_width 160
    set ::smartnic_net_period_ns 3.200
    set ::smartnic_l2_period_ns 3.200
} elseif {$configuration eq "800g"} {
    set lane_width 320
    set ::smartnic_net_period_ns 3.200
    set ::smartnic_l2_period_ns 2.560
} else {
    error "Configuration must be 400g or 800g"
}
if {$flow_mode ne "synth" && $flow_mode ne "route"} {
    error "Flow mode must be synth or route"
}
foreach value [list $jobs $bank_depth $rx_fifo_depth $tx_fifo_words] {
    if {![string is integer -strict $value] || $value <= 0} {
        error "Jobs and size parameters must be positive integers"
    }
}

file mkdir $report_dir
set_param general.maxThreads $jobs
set_param synth.maxThreads $jobs

source [file join $script_dir generated_sources.tcl]
set rtl_sources [smartnic_generated_sources $generated_dir]
read_verilog -sv $rtl_sources
read_xdc [file join $script_dir smartnic_ooc.xdc]

set generics [list \
    LANE_WIDTH=$lane_width \
    BANK_DEPTH=$bank_depth \
    RX_FIFO_DEPTH=$rx_fifo_depth \
    TX_FIFO_WORDS=$tx_fifo_words]

puts "SMARTNIC_BUILD configuration=$configuration lane_width=$lane_width part=$part_name mode=$flow_mode"
puts "SMARTNIC_CLOCKS net=${::smartnic_net_period_ns}ns l2=${::smartnic_l2_period_ns}ns"
puts "SMARTNIC_GENERICS $generics"
puts "SMARTNIC_SYNTHESIS_DIRECTIVE $synthesis_directive"

synth_design -top SmartNIC -part $part_name -mode out_of_context \
    -flatten_hierarchy none -directive $synthesis_directive -generic $generics

report_utilization -file [file join $report_dir utilization_synth.rpt]
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $report_dir utilization_hierarchical_synth.rpt]
report_timing_summary -delay_type min_max -max_paths 100 \
    -report_unconstrained -file [file join $report_dir timing_synth.rpt]
report_design_analysis -logic_level_distribution \
    -file [file join $report_dir logic_levels_synth.rpt]
report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file [file join $report_dir high_fanout_synth.rpt]
report_clock_interaction \
    -file [file join $report_dir clock_interaction_synth.rpt]
report_cdc -details -file [file join $report_dir cdc_synth.rpt]
report_methodology -file [file join $report_dir methodology_synth.rpt]
write_checkpoint -force [file join $report_dir SmartNIC_synth.dcp]
puts "SMARTNIC_SYNTH_CHECKPOINT=[file join $report_dir SmartNIC_synth.dcp]"

if {$flow_mode eq "route"} {
    opt_design
    place_design
    phys_opt_design
    route_design

    report_route_status -file [file join $report_dir route_status.rpt]
    report_utilization -file [file join $report_dir utilization_route.rpt]
    report_utilization -hierarchical -hierarchical_depth 8 \
        -file [file join $report_dir utilization_hierarchical_route.rpt]
    report_timing_summary -delay_type min_max -max_paths 100 \
        -report_unconstrained -file [file join $report_dir timing_route.rpt]
    report_clock_utilization \
        -file [file join $report_dir clock_utilization_route.rpt]
    report_clock_interaction \
        -file [file join $report_dir clock_interaction_route.rpt]
    report_cdc -details -file [file join $report_dir cdc_route.rpt]
    report_design_analysis -logic_level_distribution \
        -file [file join $report_dir logic_levels_route.rpt]
    report_design_analysis -congestion \
        -file [file join $report_dir congestion_route.rpt]
    report_drc -file [file join $report_dir drc_route.rpt]
    write_checkpoint -force [file join $report_dir SmartNIC_route.dcp]
    puts "SMARTNIC_ROUTE_CHECKPOINT=[file join $report_dir SmartNIC_route.dcp]"
}

puts "SMARTNIC_BUILD_COMPLETE configuration=$configuration mode=$flow_mode report_dir=$report_dir"
