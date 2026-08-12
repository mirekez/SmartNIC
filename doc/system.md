# System and PCIe

The board routes only PCIe lane 0, so System targets PCIe Gen2 x1. It uses one
RX/TX queue pair and one descriptor ring in each direction. The host-facing
AXI4 or Avalon interface is 64 bits at 125 MHz.

Processing queues remain 256 bits. `MasterDMA` splits every queue word into up
to four 64-bit host writes and combines up to four 64-bit host reads into one
queue word. Byte masks, partial final beats, SOP/EOP, scatter-gather fragments,
and completion accounting are covered in both AXI4 and Avalon tests.

The 64-bit fabric is wider than the useful payload rate of PCIe Gen2 x1. It is
not intended to carry all 20 Gb/s to the host; capture firmware samples every
100th descriptor.
