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

set generated_dir [file join $repo_dir rtl generated]
# These optional Tribe blocks are intentionally disabled in Config.h. Keeping
# stale generated module files in the source tree is useful for other builds,
# but excluding them here makes the FPGA resource configuration unambiguous.
set generated_sources {}
foreach source [glob -directory $generated_dir *.sv] {
    if {[lsearch -exact {MMU_TLB.sv InterruptController.sv PacketParser.sv} \
            [file tail $source]] < 0} {
        lappend generated_sources $source
    }
}
add_files -norecurse $generated_sources
add_files -norecurse [file join $script_dir rtl PacketParser_fpga.sv]
add_files -norecurse [file join $script_dir rtl klusterlab_top.sv]
add_files -fileset constrs_1 -norecurse \
    [file join $script_dir klusterlab_r2.xdc]
set_property top klusterlab_top [current_fileset]
update_compile_order -fileset sources_1

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
puts "Created [file join $build_dir open_switch.xpr]"
