# Network RTL

`Network<64, ...>` accepts two independent 64-bit 10GbE MAC words per
156.25 MHz cycle. The input balancer, parser, two RxFIFOs, banked RxRAM, two
TxFIFOs, and output merger all run in that domain.

`SmartNIC` exposes one packet-read command channel to processing and two packet
transmit streams. `PacketStream` converts 64-bit network words to/from 256-bit
processing words synchronously and preserves `keep`, `sop`, and `eop`.

The integration test uses two 10GBASE-R PCS lanes and checks RX parsing,
descriptor generation, byte-exact RxRAM reads, TX merging, minimum IPG, and
absence of receive backpressure.
