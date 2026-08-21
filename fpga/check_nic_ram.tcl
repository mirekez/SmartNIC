set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set generated_dir [file join $repo_dir rtl generated]
set work_dir [file join $script_dir build network_area_check]
set_param general.maxThreads 4
set flatten_mode rebuilt
if {$argc > 0} {
    set flatten_mode [lindex $argv 0]
}

file mkdir $work_dir
create_project network_area_check $work_dir -part xc7k325tffg676-3 -force
add_files -norecurse [glob -directory $generated_dir *.sv]
set_property top Network [current_fileset]
update_compile_order -fileset sources_1
synth_design -top Network -part xc7k325tffg676-3 -mode out_of_context \
    -generic ENABLE_RAW=0 -directive AreaOptimized_high -resource_sharing on \
    -flatten_hierarchy $flatten_mode
report_utilization -file [file join $work_dir utilization.rpt]
set brams [get_cells -hierarchical -filter {REF_NAME =~ RAMB18* || REF_NAME =~ RAMB36*}]
puts "NIC_RAM_BRAM_CELLS=[llength $brams]"
if {[llength $brams] == 0} {
    error "Network packet storage was not mapped to block RAM"
}
