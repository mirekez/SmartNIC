# 2x10G architecture

The implementation has three clocked regions:

| Region | Clock | Datapath |
|---|---:|---:|
| Network and processing | 156.25 MHz | 2 x 64-bit Ethernet, 256-bit packets |
| System/PCIe | 125 MHz | 64-bit host master/control |
| GTX serial | 10.3125 Gb/s per Ethernet lane | 64B/66B 10GBASE-R |

Two network inputs feed two RxFIFO writers and the banked RxRAM. A single
descriptor stream and one RxRAM read port serve one Tribe processing cluster.
Network-to-processing traffic is synchronous; the old asynchronous boundary
was removed. System retains asynchronous FIFOs because its PCIe user clock is
different.

The System controller contains one RX descriptor ring, one TX descriptor ring,
one queue pair, and one host DMA. Packet-side 256-bit words are serialized into
four 64-bit host transactions.
