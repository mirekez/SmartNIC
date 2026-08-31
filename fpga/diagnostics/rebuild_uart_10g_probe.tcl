set script_dir [file normalize [file dirname [info script]]]
set project_dir [file join $script_dir build uart_10g_probe]
open_project [file join $project_dir uart_10g_probe.xpr]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "UART 10G probe rebuild failed: [get_property STATUS [get_runs impl_1]]"
}
set run_dir [get_property DIRECTORY [get_runs impl_1]]
foreach extension {bit bin} {
    set source [file join $run_dir uart_10g_probe_top.$extension]
    set destination [file join $script_dir uart_10g_probe.$extension]
    file copy -force $source $destination
    puts "UART_10G_PROBE_ARTIFACT=$destination"
}
