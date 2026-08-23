# Report one implementation checkpoint without modifying the active project run.
# Usage:
#   vivado -mode batch -source report_checkpoint_timing.tcl \
#     -tclargs <checkpoint.dcp> <report-directory>

if {$argc != 2} {
    error "usage: report_checkpoint_timing.tcl <checkpoint.dcp> <report-directory>"
}

set checkpoint [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir
open_checkpoint $checkpoint

report_timing_summary -delay_type max -max_paths 1000 \
    -file [file join $report_dir timing_summary.rpt]
report_clock_interaction \
    -file [file join $report_dir clock_interaction.rpt]

set eth_clock [get_clocks -quiet eth_refclk_p]
if {[llength $eth_clock] != 0} {
    report_timing -delay_type max -from $eth_clock -to $eth_clock \
        -max_paths 100 -nworst 10 -path_type full_clock_expanded \
        -file [file join $report_dir ethernet_top100.rpt]
}

proc emit_path {channel label path} {
    if {[llength $path] == 0} {
        return
    }
    puts $channel [join [list \
        $label \
        [get_property -quiet SLACK $path] \
        [get_property -quiet DATAPATH_DELAY $path] \
        [get_property -quiet LOGIC_LEVELS $path] \
        [get_property -quiet STARTPOINT_PIN $path] \
        [get_property -quiet ENDPOINT_PIN $path]] "\t"]
}

set table [open [file join $report_dir ethernet_module_wns.tsv] w]
puts $table "scope\tslack_ns\tdatapath_ns\tlogic_levels\tstartpoint\tendpoint"

# These buckets cover the complete Networking-to-System datapath.  Restrict
# both launch and capture clocks so an unrelated CDC path cannot hide the
# synchronous Ethernet-domain result for a module.
set module_buckets [list \
    [list Processing.All             "processing/*"] \
    [list Processing.CPU             "processing/*cpu/*"] \
    [list Processing.L2Cache         "processing/*cpu/tribe/l2cache/*"] \
    [list Processing.DescriptorFetch "processing/*descriptor_fetcher/*"] \
    [list Processing.PacketDMA       "processing/*packet_dma/*"] \
    [list Network.All                "nic/network/*"] \
    [list Network.InputBalancer      "nic/network/balancer/*"] \
    [list Network.PacketParser       "nic/network/*parser/*"] \
    [list Network.RxRAM              "nic/network/rx_ram/*"] \
    [list Network.RxFifo             "nic/network/rx_fifo/*"] \
    [list Network.OutputMerger       "nic/network/output_merger/*"] \
    [list NIC.All                    "nic/*"]]

if {[llength $eth_clock] != 0} {
    foreach bucket $module_buckets {
        lassign $bucket label pattern
        set cells [get_cells -hierarchical -quiet -filter \
            "NAME =~ $pattern && IS_SEQUENTIAL == 1"]
        if {[llength $cells] == 0} {
            continue
        }
        set path [get_timing_paths -quiet -delay_type max \
            -from $eth_clock -to $cells -max_paths 1 -nworst 1]
        emit_path $table $label $path
    }
}
close $table

report_utilization -hierarchical -hierarchical_depth 4 \
    -file [file join $report_dir utilization_hierarchical.rpt]
report_route_status -file [file join $report_dir route_status.rpt]

puts "CHECKPOINT_TIMING_REPORT_DIR=$report_dir"
