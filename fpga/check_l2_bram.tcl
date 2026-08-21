set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set generated_dir [file join $repo_dir rtl generated]
set work_dir [file join $script_dir build l2_bram_check]
set_param general.maxThreads 1

file mkdir $work_dir
create_project l2_bram_check $work_dir -part xc7k325tffg676-3 -force
set sources [glob -directory $generated_dir *_pkg.sv]
lappend sources [file join $generated_dir L2Cache.sv]
add_files -norecurse $sources
set_property top L2Cache [current_fileset]
synth_design -top L2Cache -part xc7k325tffg676-3 -mode out_of_context \
    -generic CACHE_SIZE=65536 -generic PORT_BITWIDTH=256 \
    -generic CACHE_LINE_SIZE=32 -generic WAYS=4 \
    -generic ADDR_BITS=32 -generic MEM_ADDR_BITS=31 \
    -generic MEM_PORTS=4 -generic CPU_PORTS=4
report_utilization -file [file join $work_dir utilization.rpt]
set brams [get_cells -hierarchical -filter {REF_NAME =~ RAMB18* || REF_NAME =~ RAMB36*}]
puts "L2_BRAM_CELLS=[llength $brams]"
