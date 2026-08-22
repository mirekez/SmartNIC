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

# KlusterLab routes PCIe bank 116 channel 3 as a Gen2 x1 endpoint.  BAR0 maps
# one MiB of host MMIO space to System address zero.  The outbound AXI window
# covers the complete 32-bit address space and translates it without offset.
create_ip -vlnv xilinx.com:ip:axi_pcie:2.9 -module_name pcie_bridge
set_property -dict [list \
    CONFIG.INCLUDE_RC {PCI_Express_Endpoint_device} \
    CONFIG.REF_CLK_FREQ {100_MHz} \
    CONFIG.SLOT_CLOCK_CONFIG {true} \
    CONFIG.NO_OF_LANES {X1} \
    CONFIG.MAX_LINK_SPEED {5.0_GT/s} \
    CONFIG.VENDOR_ID {0x10EE} \
    CONFIG.DEVICE_ID {0x7032} \
    CONFIG.SUBSYSTEM_VENDOR_ID {0x10EE} \
    CONFIG.SUBSYSTEM_ID {0x0001} \
    CONFIG.CLASS_CODE {0x020000} \
    CONFIG.BAR0_ENABLED {true} \
    CONFIG.BAR0_TYPE {Memory} \
    CONFIG.BAR0_SCALE {Megabytes} \
    CONFIG.BAR0_SIZE {1} \
    CONFIG.PCIEBAR2AXIBAR_0 {0x00000000} \
    CONFIG.S_AXI_ID_WIDTH {4} \
    CONFIG.S_AXI_ADDR_WIDTH {32} \
    CONFIG.S_AXI_DATA_WIDTH {64} \
    CONFIG.M_AXI_ADDR_WIDTH {32} \
    CONFIG.M_AXI_DATA_WIDTH {64} \
    CONFIG.AXIBAR_NUM {1} \
    CONFIG.AXIBAR_0 {0x00000000} \
    CONFIG.AXIBAR_HIGHADDR_0 {0xFFFFFFFF} \
    CONFIG.AXIBAR2PCIEBAR_0 {0x00000000} \
    CONFIG.PCIE_BLK_LOCN {X0Y0} \
    CONFIG.shared_logic_in_core {false}] [get_ips pcie_bridge]

# PCIe MMIO can arrive as AXI4 bursts, while the register/ring endpoint is a
# single-beat AXI4 subset.  This converter legally splits bursts and presents
# AXI4-Lite transactions without placing protocol adaptation in custom RTL.
create_ip -vlnv xilinx.com:ip:axi_protocol_converter:2.1 \
    -module_name pcie_control_converter
set_property -dict [list \
    CONFIG.ADDR_WIDTH {32} \
    CONFIG.DATA_WIDTH {64} \
    CONFIG.SI_PROTOCOL {AXI4} \
    CONFIG.MI_PROTOCOL {AXI4LITE} \
    CONFIG.CLK.FREQ_HZ {125000000}] [get_ips pcie_control_converter]
generate_target all [get_ips {pcie_bridge pcie_control_converter}]

# A single capture domain is clocked by the 156.25 MHz Ethernet/system clock.
# Vivado Basic permits one ILA with at most five probes, so related status
# signals are packed into buses without dropping any system-status fields.
create_ip -vlnv xilinx.com:ip:ila:6.2 -module_name ila_system
set_property -dict [list \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_NUM_OF_PROBES {5} \
    CONFIG.C_PROBE0_WIDTH {20} \
    CONFIG.C_PROBE1_WIDTH {16} \
    CONFIG.C_PROBE1_TYPE {1} \
    CONFIG.C_PROBE2_WIDTH {32} \
    CONFIG.C_PROBE2_TYPE {1} \
    CONFIG.C_PROBE3_WIDTH {32} \
    CONFIG.C_PROBE3_TYPE {1} \
    CONFIG.C_PROBE4_WIDTH {12} \
    CONFIG.C_PROBE4_TYPE {1}] [get_ips ila_system]
generate_target all [get_ips ila_system]

set generated_dir [file join $repo_dir rtl generated]
set generated_sources [glob -directory $generated_dir *.sv]
# Current CppHDL embeds L2CacheRamBank in L2Cache.sv.  Ignore a stale leaf
# left by older generated trees so Vivado cannot bind the obsolete port list.
set legacy_l2_bank [file join $generated_dir L2CacheRamBank.sv]
set legacy_l2_index [lsearch -exact $generated_sources $legacy_l2_bank]
if {$legacy_l2_index >= 0} {
    set generated_sources [lreplace $generated_sources \
        $legacy_l2_index $legacy_l2_index]
}
add_files -norecurse $generated_sources
add_files -norecurse [list \
    [file join $script_dir rtl axi_boot_bram.sv] \
    [file join $script_dir rtl pcie_system.sv] \
    [file join $script_dir rtl klusterlab_top.sv] \
    [file join $build_dir capture.mem]]
add_files -fileset constrs_1 -norecurse [list \
    [file join $script_dir klusterlab_r2.xdc] \
    [file join $script_dir smartnic_system_cdc.xdc]]
# smartnic_cdc.xdc documents the constrained 2:1 CPU/L2-clock variant.  This
# board intentionally uses one clock for Processing/L1/L2/Network, so those
# CPU cache exceptions must not be loaded here.  System's independent PCIe
# clock crossings are constrained by smartnic_system_cdc.xdc above.
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
