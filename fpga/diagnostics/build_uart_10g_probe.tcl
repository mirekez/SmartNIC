set script_dir [file normalize [file dirname [info script]]]
set fpga_dir [file dirname $script_dir]
set repo_dir [file dirname $fpga_dir]
set project_dir [file join $script_dir build uart_10g_probe]

create_project -force uart_10g_probe $project_dir -part xc7k325tffg676-3
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

create_ip -vlnv xilinx.com:ip:axi_10g_ethernet:3.1 \
    -module_name eth10g_master
set_property -dict [list \
    CONFIG.SupportLevel {1} CONFIG.base_kr {BASE-R} \
    CONFIG.MAC_and_BASER_32 {64bit} CONFIG.Management_Interface {false} \
    CONFIG.Statistics_Gathering {false} CONFIG.DClkRate {50.00}] \
    [get_ips eth10g_master]
create_ip -vlnv xilinx.com:ip:axi_10g_ethernet:3.1 \
    -module_name eth10g_slave
create_ip -vlnv xilinx.com:ip:axi_10g_ethernet:3.1 \
    -module_name eth10g_slave2
create_ip -vlnv xilinx.com:ip:axi_10g_ethernet:3.1 \
    -module_name eth10g_slave3
foreach slave {eth10g_slave eth10g_slave2 eth10g_slave3} {
    set_property -dict [list \
        CONFIG.SupportLevel {0} CONFIG.base_kr {BASE-R} \
        CONFIG.MAC_and_BASER_32 {64bit} CONFIG.Management_Interface {false} \
        CONFIG.Statistics_Gathering {false} CONFIG.DClkRate {50.00}] \
        [get_ips $slave]
}
generate_target all [get_ips {eth10g_master eth10g_slave eth10g_slave2 eth10g_slave3}]

add_files -norecurse [list \
    [file join $repo_dir rtl generated Predef_pkg.sv] \
    [file join $repo_dir rtl generated UARTProbe.sv] \
    [file join $repo_dir rtl generated UARTProbeMemory.sv] \
    [file join $script_dir sfp_i2c_diag.sv] \
    [file join $script_dir uart_10g_probe_top.sv]]
add_files -fileset constrs_1 -norecurse [list \
    [file join $script_dir uart_10g_probe.xdc] \
    [file join $script_dir uart_10g_probe_cdc.xdc]]
set_property top uart_10g_probe_top [current_fileset]
update_compile_order -fileset sources_1

set_property strategy Flow_RuntimeOptimized [get_runs synth_1]
set_property strategy Performance_Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]

launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "UART 10G probe implementation failed: [get_property STATUS [get_runs impl_1]]"
}

set run_dir [get_property DIRECTORY [get_runs impl_1]]
foreach extension {bit bin} {
    set source [file join $run_dir uart_10g_probe_top.$extension]
    set destination [file join $script_dir uart_10g_probe.$extension]
    file copy -force $source $destination
    puts "UART_10G_PROBE_ARTIFACT=$destination"
}
