set probe_counter_sync_regs [get_cells -quiet -hierarchical -filter {
    IS_SEQUENTIAL == 1 && (
        NAME =~ *probe_clocks_gray_sync*_reg* ||
        NAME =~ *probe_activity_gray_sync*_reg*)}]
set probe_level_sync_regs [get_cells -quiet -hierarchical -filter {
    IS_SEQUENTIAL == 1 && (
        NAME =~ *probe_flags_sync*_reg* ||
        NAME =~ *probe_status_sync*_reg*)}]
set_property ASYNC_REG TRUE $probe_counter_sync_regs
set_property ASYNC_REG TRUE $probe_level_sync_regs

set probe_clock_sync1 [get_cells -quiet -hierarchical -filter {
    IS_SEQUENTIAL == 1 && NAME =~ *probe_clocks_gray_sync1_reg*}]
set probe_activity_sync1 [get_cells -quiet -hierarchical -filter {
    IS_SEQUENTIAL == 1 && NAME =~ *probe_activity_gray_sync1_reg*}]
set probe_net_counter_sources [get_cells -quiet -hierarchical -filter {
    IS_SEQUENTIAL == 1 && NAME =~ *probe_net_clock_count_reg*}]
set probe_txusr_counter_sources [get_cells -quiet -hierarchical -filter {
    IS_SEQUENTIAL == 1 && NAME =~ *probe_txusr_clock_count_reg*}]
set probe_activity_sources [get_cells -quiet -hierarchical -filter {
    IS_SEQUENTIAL == 1 && (
        NAME =~ *probe_rx*_count_reg* || NAME =~ *probe_tx*_count_reg*)}]

set_max_delay -datapath_only 6.400 -from $probe_net_counter_sources \
    -to $probe_clock_sync1
set_bus_skew 6.400 -from $probe_net_counter_sources -to $probe_clock_sync1
set_max_delay -datapath_only 6.400 -from $probe_txusr_counter_sources \
    -to $probe_clock_sync1
set_bus_skew 6.400 -from $probe_txusr_counter_sources -to $probe_clock_sync1
set_max_delay -datapath_only 6.400 -from $probe_activity_sources \
    -to $probe_activity_sync1
set_bus_skew 6.400 -from $probe_activity_sources -to $probe_activity_sync1

set probe_level_sync1 [get_cells -quiet -hierarchical -filter {
    IS_SEQUENTIAL == 1 && (
        NAME =~ *probe_flags_sync1_reg* ||
        NAME =~ *probe_status_sync1_reg*)}]
set_false_path -to $probe_level_sync1
