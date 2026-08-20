set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set build_dir [file normalize [file join $script_dir build]]
set part xc7k160tffg676-3

file mkdir $build_dir
create_project open_switch $build_dir -part $part -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

create_ip -vlnv xilinx.com:ip:axi_10g_ethernet:3.1 \
    -module_name eth10g_master
set_property -dict [list \
    CONFIG.SupportLevel {1} \
    CONFIG.base_kr {BASE-R} \
    CONFIG.MAC_and_BASER_32 {64bit} \
    CONFIG.Management_Interface {false} \
    CONFIG.Statistics_Gathering {false} \
    CONFIG.DClkRate {50.00}] [get_ips eth10g_master]

create_ip -vlnv xilinx.com:ip:axi_10g_ethernet:3.1 \
    -module_name eth10g_slave
set_property -dict [list \
    CONFIG.SupportLevel {0} \
    CONFIG.base_kr {BASE-R} \
    CONFIG.MAC_and_BASER_32 {64bit} \
    CONFIG.Management_Interface {false} \
    CONFIG.Statistics_Gathering {false} \
    CONFIG.DClkRate {50.00}] [get_ips eth10g_slave]
generate_target all [get_ips {eth10g_master eth10g_slave}]

# Three independent capture domains are intentionally clocked by the 156.25
# MHz Ethernet/system clock.  The system ILA observes reset/GTX/CPU status;
# one ILA per port captures the complete 64-bit MAC RX and TX interfaces.
create_ip -vlnv xilinx.com:ip:ila:6.2 -module_name ila_system
set_property -dict [list \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_NUM_OF_PROBES {8} \
    CONFIG.C_PROBE0_WIDTH {17} \
    CONFIG.C_PROBE1_WIDTH {8} \
    CONFIG.C_PROBE1_TYPE {1} \
    CONFIG.C_PROBE2_WIDTH {8} \
    CONFIG.C_PROBE2_TYPE {1} \
    CONFIG.C_PROBE3_WIDTH {8} \
    CONFIG.C_PROBE3_TYPE {1} \
    CONFIG.C_PROBE4_WIDTH {8} \
    CONFIG.C_PROBE4_TYPE {1} \
    CONFIG.C_PROBE5_WIDTH {16} \
    CONFIG.C_PROBE5_TYPE {1} \
    CONFIG.C_PROBE6_WIDTH {12} \
    CONFIG.C_PROBE6_TYPE {1} \
    CONFIG.C_PROBE7_WIDTH {16} \
    CONFIG.C_PROBE7_TYPE {1}] [get_ips ila_system]

foreach channel {0 1} {
    set ila_name ila_eth${channel}
    create_ip -vlnv xilinx.com:ip:ila:6.2 -module_name $ila_name
    set_property -dict [list \
        CONFIG.C_DATA_DEPTH {1024} \
        CONFIG.C_NUM_OF_PROBES {15} \
        CONFIG.C_PROBE0_WIDTH {64} \
        CONFIG.C_PROBE0_TYPE {1} \
        CONFIG.C_PROBE1_WIDTH {8} \
        CONFIG.C_PROBE1_TYPE {1} \
        CONFIG.C_PROBE2_WIDTH {1} \
        CONFIG.C_PROBE3_WIDTH {1} \
        CONFIG.C_PROBE4_WIDTH {1} \
        CONFIG.C_PROBE5_WIDTH {64} \
        CONFIG.C_PROBE5_TYPE {1} \
        CONFIG.C_PROBE6_WIDTH {8} \
        CONFIG.C_PROBE6_TYPE {1} \
        CONFIG.C_PROBE7_WIDTH {1} \
        CONFIG.C_PROBE8_WIDTH {1} \
        CONFIG.C_PROBE9_WIDTH {1} \
        CONFIG.C_PROBE10_WIDTH {8} \
        CONFIG.C_PROBE10_TYPE {1} \
        CONFIG.C_PROBE11_WIDTH {1} \
        CONFIG.C_PROBE12_WIDTH {1} \
        CONFIG.C_PROBE13_WIDTH {8} \
        CONFIG.C_PROBE13_TYPE {1} \
        CONFIG.C_PROBE14_WIDTH {8} \
        CONFIG.C_PROBE14_TYPE {1}] [get_ips $ila_name]
}
generate_target all [get_ips {ila_system ila_eth0 ila_eth1}]

set generated_dir [file join $repo_dir rtl generated]
set generated_sources [glob -directory $generated_dir *.sv]
add_files -norecurse $generated_sources
add_files -norecurse [list \
    [file join $script_dir rtl axi_boot_bram.sv] \
    [file join $script_dir rtl klusterlab_top.sv] \
    [file join $build_dir capture.mem]]
add_files -fileset constrs_1 -norecurse \
    [file join $script_dir klusterlab_r2.xdc]
set_property top klusterlab_top [current_fileset]
update_compile_order -fileset sources_1

set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
puts "Created [file join $build_dir open_switch.xpr]"
