set script_dir [file dirname [file normalize [info script]]]
# The four-core Tribe hierarchy can exceed a 10 GiB VM when Vivado starts its
# default seven synthesis workers.  One internal thread is slower but bounded.
set_param general.maxThreads 1
source [file join $script_dir create_project.tcl]
# One job keeps peak RAM below the limits of typical development VMs while
# Vivado elaborates four CPU cores and two licensed 10G Ethernet subsystems.
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
open_run impl_1
report_utilization -file [file join $script_dir build utilization.rpt]
report_timing_summary -file [file join $script_dir build timing_summary.rpt]
set bitfiles [get_property PROGRESS [get_runs impl_1]]
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation did not complete: [get_property STATUS [get_runs impl_1]]"
}
file copy -force [file join $script_dir build open_switch.runs impl_1 klusterlab_top.bit] \
    [file join $script_dir open_switch.bit]
puts "BITSTREAM=[file join $script_dir open_switch.bit]"
