set script_dir [file normalize [file dirname [info script]]]
set fpga_dir [file dirname $script_dir]
set output_dir [file join $script_dir build]
file mkdir $output_dir

proc build_uart_diag {script_dir fpga_dir output_dir name top xdc} {
    set project_dir [file join $output_dir $name]
    create_project -force $name $project_dir -part xc7k325tffg676-3
    set_property target_language Verilog [current_project]
    add_files -norecurse [list \
        [file join $fpga_dir rtl uart_banner_tx.sv] \
        [file join $script_dir ${top}.sv]]
    add_files -fileset constrs_1 -norecurse [file join $script_dir $xdc]
    set_property top $top [current_fileset]
    set_property strategy Flow_RuntimeOptimized [get_runs synth_1]
    set_property strategy Flow_RuntimeOptimized [get_runs impl_1]
    set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]

    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        error "$name synthesis failed"
    }
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
        error "$name implementation failed: [get_property STATUS [get_runs impl_1]]"
    }

    set run_dir [get_property DIRECTORY [get_runs impl_1]]
    foreach extension {bit bin} {
        set source [file join $run_dir ${top}.${extension}]
        set destination [file join $script_dir ${name}.${extension}]
        file copy -force $source $destination
        puts "UART_DIAG_ARTIFACT=$destination"
    }
    close_project
}

build_uart_diag $script_dir $fpga_dir $output_dir \
    uart_diag_A17_sysclk uart_diag_sysclk_top uart_diag_sysclk.xdc
build_uart_diag $script_dir $fpga_dir $output_dir \
    uart_diag_A17_ethclk uart_diag_ethclk_top uart_diag_ethclk.xdc
