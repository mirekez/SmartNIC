set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir build open_switch.xpr]
set report_dir [file join $script_dir build]
set checkpoint [file join $script_dir build open_switch.runs impl_1 \
    klusterlab_top_routed.dcp]

if {[file exists $checkpoint]} {
    open_checkpoint $checkpoint
} else {
    open_project $project_file
    open_run impl_1
}

proc clock_name {clock_object} {
    if {[llength $clock_object] == 0} {
        return "<none>"
    }
    set name [get_property -quiet NAME $clock_object]
    return [expr {$name eq "" ? $clock_object : $name}]
}

proc emit_path {channel scope path} {
    if {[llength $path] == 0} {
        return
    }
    set start_clock [clock_name [get_property -quiet STARTPOINT_CLOCK $path]]
    set end_clock [clock_name [get_property -quiet ENDPOINT_CLOCK $path]]
    puts $channel [join [list \
        $scope \
        $start_clock \
        $end_clock \
        [get_property -quiet SLACK $path] \
        [get_property -quiet DATAPATH_DELAY $path] \
        [get_property -quiet LOGIC_LEVELS $path] \
        [get_property -quiet STARTPOINT_PIN $path] \
        [get_property -quiet ENDPOINT_PIN $path]] "\t"]
}

set table_file [file join $report_dir clock_module_wns.tsv]
set table [open $table_file w]
puts $table "scope\tlaunch_clock\tcapture_clock\tslack_ns\tdatapath_ns\tlogic_levels\tstartpoint\tendpoint"

# One row per capture clock gives the true clock-domain WNS without allowing
# the much larger CPU path population to hide smaller clock domains.
foreach capture_clock [lsort -dictionary [get_clocks -quiet]] {
    set path [get_timing_paths -quiet -delay_type max -to $capture_clock \
        -max_paths 1 -nworst 1]
    emit_path $table "CLOCK:[clock_name $capture_clock]" $path
}

# Stable hierarchy buckets make the refreshed result directly comparable even
# when generate indices or synthesized leaf names change between conversions.
set module_buckets [list \
    [list Processing.All "processing/*"] \
    [list CPU.All "processing/*cpu/*"] \
    [list CPU.Cores "processing/*cpu/tribe/*cores/*"] \
    [list CPU.Decode "processing/*cpu/tribe/*cores/dec/*"] \
    [list CPU.Execute "processing/*cpu/tribe/*cores/exe/*"] \
    [list CPU.ExecuteMem "processing/*cpu/tribe/*cores/exe_mem/*"] \
    [list CPU.Writeback "processing/*cpu/tribe/*cores/wb/*"] \
    [list CPU.WritebackMem "processing/*cpu/tribe/*cores/wb_mem/*"] \
    [list CPU.CSR "processing/*cpu/tribe/*cores/csr/*"] \
    [list CPU.RegisterFile "processing/*cpu/tribe/*cores/regs/*"] \
    [list CPU.ICache "processing/*cpu/tribe/*cores/icache/*"] \
    [list CPU.DCache "processing/*cpu/tribe/*cores/dcache/*"] \
    [list CPU.L1L2_CDC "processing/*cpu/tribe/*mem_cdc/*"] \
    [list CPU.L2Cache "processing/*cpu/tribe/l2cache/*"] \
    [list Processing.DescriptorFetcher "processing/*descriptor_fetcher/*"] \
    [list Processing.PacketDMA "processing/*packet_dma/*"] \
    [list Network.All "nic/network/*"] \
    [list Network.InputBalancer "nic/network/balancer/*"] \
    [list Network.PacketParser "nic/network/*parser/*"] \
    [list Network.RxRAM "nic/network/rx_ram/*"] \
    [list Network.RxFifo "nic/network/rx_fifo/*"] \
    [list Network.OutputMerger "nic/network/output_merger/*"] \
    [list System.All "system/*"] \
    [list System.RxCDC "system/*rx_cdc/*"] \
    [list System.TxCDC "system/*tx_cdc/*"] \
    [list BootMemory "boot_memory/*"] \
    [list Ethernet.Channel0 "eth0/*"] \
    [list Ethernet.Channel1 "eth1/*"] \
    [list Debug.ILA "system_debug/*"] \
    [list StartupAndReset "startup_mmcm/*"]]

foreach bucket $module_buckets {
    lassign $bucket label pattern
    set cells [get_cells -hierarchical -quiet -filter \
        "NAME =~ $pattern && IS_SEQUENTIAL == 1"]
    if {[llength $cells] == 0} {
        continue
    }
    set path [get_timing_paths -quiet -delay_type max -to $cells \
        -max_paths 1 -nworst 1]
    emit_path $table "MODULE:$label" $path
}

close $table

# Record endpoint cardinality independently of report_exceptions. A zero count
# here means the name filter no longer matches the optimized hierarchy and the
# corresponding CDC exception must not be trusted.
set cdc_count_file [file join $report_dir cdc_endpoint_counts.tsv]
set cdc_count [open $cdc_count_file w]
puts $cdc_count "collection\tsequential_cells"
set cdc_collections [list \
    [list Debug.FirstStage "*dclk_toggle_meta_reg|*txusr_toggle_meta_reg|*ila_system_state_meta_reg*"] \
    [list L1L2.SyncStages "*/request_slow1_reg_reg*|*/request_slow2_reg_reg*|*/response_fast1_reg_reg*|*/response_fast2_reg_reg*"] \
    [list L1L2.RequestSource "*/read_fast_reg_reg*|*/write_fast_reg_reg*|*/addr_fast_reg_reg*|*/write_data_fast_reg_reg*|*/write_mask_fast_reg_reg*|*/cache_disable_fast_reg_reg*"] \
    [list L1L2.RequestCapture "*/read_slow_reg_reg*|*/write_slow_reg_reg*|*/addr_slow_reg_reg*|*/write_data_slow_reg_reg*|*/write_mask_slow_reg_reg*|*/cache_disable_slow_reg_reg*"] \
    [list L1L2.ResponseSource "*/read_data_slow_reg_reg*"] \
    [list L1L2.ResponseCapture "*/read_data_fast_reg_reg*"]]
foreach collection $cdc_collections {
    lassign $collection label patterns
    set count 0
    foreach pattern [split $patterns "|"] {
        incr count [llength [get_cells -hierarchical -quiet -filter \
            "IS_SEQUENTIAL == 1 && NAME =~ $pattern"]]
    }
    puts $cdc_count "$label\t$count"
}
close $cdc_count

report_timing_summary -delay_type max -max_paths 1000 \
    -file [file join $report_dir refreshed_timing_summary.rpt]
report_clock_interaction \
    -file [file join $report_dir refreshed_clock_interaction.rpt]
report_cdc -details \
    -file [file join $report_dir refreshed_cdc.rpt]
report_exceptions -coverage \
    -file [file join $report_dir refreshed_exception_coverage.rpt]

puts "CLOCK_MODULE_TIMING_TABLE=$table_file"
puts "CDC_ENDPOINT_COUNTS=$cdc_count_file"
