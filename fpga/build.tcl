set script_dir [file dirname [file normalize [info script]]]
# The generated memories are now BRAM leaf primitives, so four workers stay
# within host memory while avoiding the pathological single-thread runtime.
set_param general.maxThreads 4
set_param synth.maxThreads 4
source [file join $script_dir create_project.tcl]
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
open_run impl_1
report_utilization -file [file join $script_dir build utilization.rpt]
report_timing_summary -file [file join $script_dir build timing_summary.rpt]
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation did not complete: [get_property STATUS [get_runs impl_1]]"
}
set run_dir [file join $script_dir build open_switch.runs impl_1]
foreach extension {bit bin ltx} {
    set source [file join $run_dir klusterlab_top.$extension]
    set destination [file join $script_dir open_switch.$extension]
    if {![file exists $source]} {
        error "Missing implementation artifact: $source"
    }
    file copy -force $source $destination
    puts "FPGA_ARTIFACT=$destination"
}
