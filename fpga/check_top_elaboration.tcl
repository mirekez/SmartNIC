set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir create_project.tcl]
synth_design -rtl -rtl_skip_mlo -top klusterlab_top \
    -part xc7k325tffg676-3 -name rtl_elaboration
puts "TOP_ELABORATION_OK"
