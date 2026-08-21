set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set build_dir [file normalize [file join $script_dir build]]
set part xc7k325tffg676-3

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

# A single capture domain is clocked by the 156.25 MHz Ethernet/system clock.
# Vivado Basic permits one ILA with at most five probes, so related status
# signals are packed into buses without dropping any system-status fields.
create_ip -vlnv xilinx.com:ip:ila:6.2 -module_name ila_system
set_property -dict [list \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_NUM_OF_PROBES {5} \
    CONFIG.C_PROBE0_WIDTH {17} \
    CONFIG.C_PROBE1_WIDTH {16} \
    CONFIG.C_PROBE1_TYPE {1} \
    CONFIG.C_PROBE2_WIDTH {32} \
    CONFIG.C_PROBE2_TYPE {1} \
    CONFIG.C_PROBE3_WIDTH {16} \
    CONFIG.C_PROBE3_TYPE {1} \
    CONFIG.C_PROBE4_WIDTH {12} \
    CONFIG.C_PROBE4_TYPE {1}] [get_ips ila_system]
generate_target all [get_ips ila_system]

set generated_dir [file join $repo_dir rtl generated]
set generated_sources [glob -directory $generated_dir *.sv]
add_files -norecurse $generated_sources
add_files -norecurse [list \
    [file join $script_dir rtl axi_boot_bram.sv] \
    [file join $script_dir rtl klusterlab_top.sv] \
    [file join $build_dir capture.mem]]
add_files -fileset constrs_1 -norecurse [list \
    [file join $script_dir klusterlab_r2.xdc]]
# smartnic_cdc.xdc documents the constrained 2:1-clock variant.  This board
# intentionally uses one clock for Processing/L1/L2/Network, so those CDC and
# multicycle exceptions must not be loaded here.
set_property top klusterlab_top [current_fileset]
update_compile_order -fileset sources_1

set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on [get_runs synth_1]
# Keep timing-driven pre-route physical optimization.  The aggressive
# post-route pass is intentionally disabled: on a deeply failing architectural
# path it spent tens of minutes attempting local CPU-only transformations after
# a legal routed checkpoint had already been produced.
set_property strategy Performance_Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED false [get_runs impl_1]
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
puts "Created [file join $build_dir open_switch.xpr]"
