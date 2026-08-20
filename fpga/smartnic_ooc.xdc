# Clock periods are supplied by build.tcl before this file is read.
if {![info exists ::smartnic_net_period_ns] ||
    ![info exists ::smartnic_l2_period_ns]} {
    error "SmartNIC clock periods were not supplied by build.tcl"
}

create_clock -name net_clk -period $::smartnic_net_period_ns \
    [get_ports net_clk]
create_clock -name l2_clk -period $::smartnic_l2_period_ns \
    [get_ports l2_clk]

# The clocks are independent at the SmartNIC core boundary.  All intentional
# crossings are implemented by the Gray-pointer asynchronous FIFOs in the RTL.
set_clock_groups -asynchronous \
    -group [get_clocks net_clk] \
    -group [get_clocks l2_clk]

# Reset is an asynchronous core control and is synchronized inside each clock
# domain.  It is not a timed data input from the surrounding board shell.
set_false_path -from [get_ports reset]

# OOC boundary timing assumes the board shell registers core inputs and
# outputs.  Zero external delay therefore leaves the entire clock period for
# core logic without inventing board-specific package or PCB delays.
set net_inputs [get_ports -quiet {
    net_rx_valid_in net_rx_data_in[*] net_rx_keep_in[*]
    net_rx_sop_in[*] net_rx_eop_in[*] net_rx_raw_in net_tx_ready_in
}]
set net_outputs [get_ports -quiet {
    net_rx_ready_out net_tx_valid_out net_tx_data_out[*]
    net_tx_keep_out[*] net_tx_sop_out[*] net_tx_eop_out[*]
    protocol_error_out storage_full_out
}]
set l2_inputs [get_ports -quiet {
    l2_descriptor_ready_in l2_rx_read_valid_in[*]
    l2_rx_read_handle_in[*] l2_rx_read_length_in[*]
    l2_rx_ready_in[*] l2_tx_valid_in[*] l2_tx_data_in[*]
    l2_tx_keep_in[*] l2_tx_sop_in[*] l2_tx_eop_in[*]
}]
set l2_outputs [get_ports -quiet {
    l2_descriptor_valid_out l2_descriptor_data_out[*]
    l2_descriptor_word_out[*] l2_descriptor_sop_out
    l2_descriptor_eop_out l2_rx_read_ready_out[*]
    l2_rx_valid_out[*] l2_rx_data_out[*] l2_rx_keep_out[*]
    l2_rx_sop_out[*] l2_rx_eop_out[*] l2_tx_ready_out[*]
}]

if {[llength $net_inputs]} {
    set_input_delay 0.000 -clock net_clk $net_inputs
}
if {[llength $net_outputs]} {
    set_output_delay 0.000 -clock net_clk $net_outputs
}
if {[llength $l2_inputs]} {
    set_input_delay 0.000 -clock l2_clk $l2_inputs
}
if {[llength $l2_outputs]} {
    set_output_delay 0.000 -clock l2_clk $l2_outputs
}

