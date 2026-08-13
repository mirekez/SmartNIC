set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set generated_dir [file join $repo_dir rtl generated]
set work_dir [file join $script_dir build nic_ram_check]
set_param general.maxThreads 1

file mkdir $work_dir
create_project nic_ram_check $work_dir -part xc7k160tffg676-3 -force
add_files -norecurse [list \
    [file join $generated_dir Predef_pkg.sv] \
    [file join $generated_dir InputBalancer.sv]]
set_property top InputBalancer [current_fileset]
synth_design -top InputBalancer -part xc7k160tffg676-3 -mode out_of_context
report_utilization -file [file join $work_dir utilization.rpt]
set brams [get_cells -hierarchical -filter {REF_NAME =~ RAMB18* || REF_NAME =~ RAMB36*}]
puts "NIC_RAM_BRAM_CELLS=[llength $brams]"
if {[llength $brams] == 0} {
    error "InputBalancer packet storage was not mapped to block RAM"
}
