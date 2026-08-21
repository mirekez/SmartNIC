# Processing <-> System asynchronous-FIFO constraints.
#
# Include this XDC only in a top that instantiates System. The current Kintex
# board top bypasses System, so create_project.tcl intentionally does not add
# this file to that project.

set system_fifo_sync_regs [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && (
        NAME =~ */rx_cdc/*_gray_*1_reg_reg* ||
        NAME =~ */rx_cdc/*_gray_*2_reg_reg* ||
        NAME =~ */tx_cdc/*_gray_*1_reg_reg* ||
        NAME =~ */tx_cdc/*_gray_*2_reg_reg*)}]
set_property ASYNC_REG TRUE $system_fifo_sync_regs

# Bound each Gray-pointer crossing to one source-clock period and constrain bus
# skew so no bit can arrive a full source increment later than another bit.
# L2 is 156.25 MHz (6.4 ns); System is 125 MHz (8.0 ns).
set rx_write_gray_source [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && NAME =~ */rx_cdc/write_gray_reg_reg*}]
set rx_write_gray_capture [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && NAME =~ */rx_cdc/write_gray_read1_reg_reg*}]
set_max_delay -datapath_only 6.400 -from $rx_write_gray_source \
    -to $rx_write_gray_capture
set_bus_skew 6.400 -from $rx_write_gray_source \
    -to $rx_write_gray_capture

set rx_read_gray_source [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && NAME =~ */rx_cdc/read_gray_reg_reg*}]
set rx_read_gray_capture [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && NAME =~ */rx_cdc/read_gray_write1_reg_reg*}]
set_max_delay -datapath_only 8.000 -from $rx_read_gray_source \
    -to $rx_read_gray_capture
set_bus_skew 8.000 -from $rx_read_gray_source \
    -to $rx_read_gray_capture

set tx_write_gray_source [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && NAME =~ */tx_cdc/write_gray_reg_reg*}]
set tx_write_gray_capture [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && NAME =~ */tx_cdc/write_gray_read1_reg_reg*}]
set_max_delay -datapath_only 8.000 -from $tx_write_gray_source \
    -to $tx_write_gray_capture
set_bus_skew 8.000 -from $tx_write_gray_source \
    -to $tx_write_gray_capture

set tx_read_gray_source [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && NAME =~ */tx_cdc/read_gray_reg_reg*}]
set tx_read_gray_capture [get_cells -hierarchical -quiet -filter {
    IS_SEQUENTIAL == 1 && NAME =~ */tx_cdc/read_gray_write1_reg_reg*}]
set_max_delay -datapath_only 6.400 -from $tx_read_gray_source \
    -to $tx_read_gray_capture
set_bus_skew 6.400 -from $tx_read_gray_source \
    -to $tx_read_gray_capture

# FIFO payload memory is written in one domain and read only after its Gray
# pointer crosses. The pointer protocol and constraints above protect it.
set system_fifo_payload [get_cells -hierarchical -quiet -filter {
    NAME =~ */rx_cdc/data_mem_reg* || NAME =~ */tx_cdc/data_mem_reg*}]
set_false_path -from $system_fifo_payload
