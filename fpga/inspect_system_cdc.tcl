set script_dir [file dirname [file normalize [info script]]]
open_checkpoint [file join $script_dir build open_switch.runs synth_1 klusterlab_top.dcp]

source [file join $script_dir smartnic_system_cdc.xdc]

foreach variable {
    system_fifo_sync_regs
    rx_write_gray_source rx_write_gray_capture
    rx_read_gray_source rx_read_gray_capture
    tx_write_gray_source tx_write_gray_capture
    tx_read_gray_source tx_read_gray_capture
    system_fifo_payload system_reset_source system_l2_fifo_regs
} {
    puts "CDC_COUNT=$variable:[llength [set $variable]]"
}
