set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir build open_switch.xpr]
set_param general.maxThreads 1

if {![file exists $project_file]} {
    error "Project does not exist; run fpga/build.sh first"
}

open_project $project_file
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis did not complete: [get_property STATUS [get_runs synth_1]]"
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation did not complete: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_utilization -file [file join $script_dir build utilization.rpt]
report_timing_summary -file [file join $script_dir build timing_summary.rpt]
file copy -force \
    [file join $script_dir build open_switch.runs impl_1 klusterlab_top.bit] \
    [file join $script_dir open_switch.bit]
puts "BITSTREAM=[file join $script_dir open_switch.bit]"
