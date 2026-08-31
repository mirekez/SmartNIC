# The USB bridge TXD pin is asynchronous to net_clk. UARTProbe contains the
# required two-flop receiver synchronizer; only the first stage is exempted.
set probe_uart_rx_sync [get_cells -quiet -hierarchical -filter {
    IS_SEQUENTIAL == 1 && NAME =~ *uart_probe*rx_sync?_reg*}]
set_property ASYNC_REG TRUE $probe_uart_rx_sync
set probe_uart_rx_sync1 [get_cells -quiet -hierarchical -filter {
    IS_SEQUENTIAL == 1 && NAME =~ *uart_probe*rx_sync1_reg*}]
set_false_path -to $probe_uart_rx_sync1

# CPU mode samples only signals already synchronous to net_clk.  The older
# standalone link-status probe had additional status_async_sync registers;
# they are intentionally absent here and therefore need no constraint.

# The packet-trigger toggle and all sampled loopback signals originate in the
# same net_clk domain as UARTProbe, so they require no CDC exception.
