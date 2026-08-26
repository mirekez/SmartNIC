# One-CPU SmartNIC learning-switch video

The primary demo compiles and runs the real [`test/l2_switch.cpp`](../test/l2_switch.cpp)
regression with visualization enabled. Its Tribe firmware learns ten source
MAC addresses on each input port in four closed hash layers stored in DDR4.
The first 20 packets train the table before recording. The measured phase then
sends 400 full-size known-destination packets at 79.83% load on both ports.
PacketDMA places every packet in the lower 1 MiB DDR circular buffer and
keeps the recent working set in the complete 64 KiB L2. The upper 1 MiB
contains firmware and the MAC hash tables. All four cores inspect disjoint
packets; together they dispatch every packet across both TX ports. Each CPU
command requests a post-TX ownership release: PacketDMA sends the zero line
through Tribe's L2 DMA allocator after EOP and writes the same line to DDR, so
the cache cannot later restore the old header.
Each DDR packet slot is rendered as a 4x4-pixel cell: its left four-pixel
column is the complete 32-byte header line and turns black after the real DDR
clear response. The L2 label counts the same completed lines and its physical
cache image is updated at the corresponding cache location.

```sh
cmake -S . -B build
cmake --build build --target smartnic_l2_switch_video -j
```

Run the identical workload without video encoding:

```sh
ctest --test-dir build -R system_l2_switch_sustained_80pct --output-on-failure
```

The output is
`demo/output/smartnic_l2_switch_all_packets_v15.avi`. The executable asserts zero
ingress backpressure, all 400 measured packet reads and DDR writes, byte-exact
contents for all 400 resident packet slots, 79–81% activity on each
wire, exact MAC forwarding, and TX activity on both ports. The image compresses
the full capacity of L1, L2, and both DDR halves into their rectangles instead
of showing only the beginning/current packet. PacketDMA's hardware MMIO lock
protects only each core's staged TX command. The core releases it immediately
after enqueue, allowing other cores to inspect and fill the bounded command FIFO
while the single TX datapath transmits preceding commands.

## Sampled capture video

The demo compiles the real [`test/capture.cpp`](../test/capture.cpp) full-SoC
test with visualization enabled. It shows packet arrival through the two 10G
MAC-side channels as independent rows, per-port RX/TX FIFO occupancy,
RxRAM, coherent PacketDMA writes into the shared L2, instruction/data-cache
activity in all four Tribe cores, host queues, and the 1 MiB simulated DDR4.

```text
+---------+---------+--------+----------------------+----------+
| 2x10G   | P0 RX/TX| RX RAM | Tribe CPU            | RX QUEUE |
| P0 / P1 | P1 RX/TX| banks  | L2 + four I$/D$ cores| TX QUEUE |
+---------+---------+--------+----------------------+----------+
|                   DDR4 1 MiB / 64 bytes per pixel            |
+--------------------------------------------------------------+
```

Build and generate the AVI:

```sh
cmake -S . -B build
cmake --build build --target smartnic_capture_video -j
```

Outputs are written under `demo/output/`:

- `smartnic_2x10g_capture_4core_v4.avi` — 500x360 RLE8 animation
- `smartnic_2x10g_capture.csv` — per-frame activity counters
- `smartnic_2x10g_capture_final.png` — final still image
- event snapshots ending in `_loaded`, `_mid`, and `_queue`

Run the executable directly to select an output path or background color:

```sh
build/demo/smartnic_capture_demo build/demo/capture.elf demo/output/demo.avi '#7f7f7f'
```

Packet pixels encode little-endian 16-bit words. Demo firmware rotates packets
through thirty-two coherent 2 KiB L2 slots. Harts 1..3 divide all packet
headers between their private L1 D-caches; hart 0 owns PacketDMA and rereads
the destination/source MAC and first 40 bytes of every twentieth packet. Every
twentieth packet is sent
through the real Network TX FIFO and checked byte-for-byte at its selected MAC
port. Every fortieth packet is transferred through the System RxQueue to host
memory and checked byte-for-byte. The visualizer
keeps the four most recent completed queue transfers visible, preventing a
short live-queue residency from disappearing between decimated video frames.
RX descriptors likewise receive an eight-frame visual dwell because their real
FIFO lifetime can be shorter than one video sampling interval. TX packets enter
the drawing at PacketDMA admission and disappear at the verified external MAC
EOP; completed transmissions are not retained as FIFO contents.
Because physical TX occupancy is only about 0.13 seconds in this test, a
verified dequeue receives a 60-frame (0.5-second) visual dwell before removal.
The final still is nevertheless forced to the true empty state.

The generator sends 320 full-size packets over both channels for 38,080
uninterrupted network clocks. Each channel is active for 79.83% of that
interval. The test stops immediately on ingress backpressure or RxRAM/RxFIFO
`storage_full`, and it cannot pass until all 320 packets have reached coherent
L2. This traffic volume exceeds the receive store, so a pass demonstrates
sustained allocation, DMA drain, and storage reuse rather than burst caching.
