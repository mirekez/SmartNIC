# Device-specific physical guidance for the dense CPU SmartNIC image.
#
# DescriptorFetcher uses a four-entry, 1,280-bit distributed-RAM queue.  Its
# two read-address bits and write/assembly select terms consequently drive
# more than a thousand LUTRAM pins each.  Vivado normally declines to
# replicate these nets because only a subset of their loads is on a critical
# timing path.  That leaves long local routes through the already busy
# CPU/L2/Network neighborhood.  FORCE_MAX_FANOUT is a physical optimization
# request: it does not alter the RTL state or protocol latency.

set descriptor_queue_select_nets [get_nets -hierarchical -quiet -filter {
    (NAME =~ *descriptor_fetcher/head_reg* ||
     NAME =~ *descriptor_fetcher/tail_reg* ||
     NAME =~ *descriptor_fetcher/assembly_active_reg*) &&
    FLAT_PIN_COUNT > 1000
}]

foreach queue_select_net $descriptor_queue_select_nets {
    set_property FORCE_MAX_FANOUT 128 $queue_select_net
    puts "CONGESTION_FORCE_MAX_FANOUT=128 NET=$queue_select_net PINS=[get_property FLAT_PIN_COUNT $queue_select_net]"
}

puts "CONGESTION_FORCED_NETS=[llength $descriptor_queue_select_nets]"
