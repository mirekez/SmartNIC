# Processing

The Kintex-7 configuration instantiates one Tribe cluster, one
`DescriptorFetcher`, and one `PacketDMA`. All processing logic and its Network
boundary run at 156.25 MHz, so descriptors, RxRAM commands, receive packets,
and transmit packets connect directly without asynchronous FIFOs.

PacketDMA still exposes 256-bit framed paths to Network and System. The only
remaining packet CDC is inside System at the 156.25 MHz to 125 MHz boundary.
