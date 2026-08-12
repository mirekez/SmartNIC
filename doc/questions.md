# Architecture questions

## Resolved for the current functional model

- Both 400G (`8 x 160`) and 800G (`8 x 320`) variants are built and tested.
- Current integration uses `N=8` Tribe clusters, four cores per cluster.
- Network clock is 312.5 MHz; L2 is exact-rate at 195.3125/390.625 MHz;
  primary CPU clock is four times L2; System test clock is 256 MHz.
- Processing exports one DDR AXI master per cluster.
- System currently uses eight 256-bit RX/TX queue pairs and a 512-bit Avalon
  host interface at 256 MHz; AXI4 is compile-time selectable.
- The capture firmware drains all RxRAM packets and sends every tenth packet
  directly through PacketDMA to a host queue; ordinary L2 copy modes remain
  available and independently tested.
- Global packet order is not guaranteed across balanced streams; order is a
  queue/flow policy decision.
- The current descriptor is 160 bytes: 32-byte common header plus 128-byte view.

## Blocking for the first RTL milestone

1. Which FPGA family, part and speed grade is the first target?
   - Determines RAM type, clock feasibility and PCIe wrapper.
2. Is the first milestone 400G only, with 800G parameterized but not timing-closed?
   - Recommended until 390.625 MHz L2 timing and exact-rate CDC behavior are closed.
3. What is the exact MAC/PCS adapter contract?
   - Define byte/lane order, preamble/FCS ownership, idles and error signals.
   - Confirm that the eight input lanes form one time-ordered aggregate stream, not eight pre-separated frame streams.
4. What maximum frame size and required RX buffering interval are needed?
   - Determines cell size and RX-RAM capacity.
5. Must all eight tested Processing clusters be present in the first product,
   or may a lower-`N` build trade throughput for area?
   - Determines L2 ports, queue count, interrupts and RAM arbitration.
6. Must DMA into L2 be coherent with cached CPU mappings?
   - Recommended: yes, using the existing external coherent L2 slave path after burst upgrades.
7. Which traffic must reach the host at line rate: RX, TX, or simultaneous full duplex?
   - Determines the minimum attach bandwidth and packet-RAM port budget.
8. Which PCIe hard block and transaction-stream interface will be used?
   - The portable boundary can then be bound and tested.

## Packet and queue semantics

1. Confirm the proposed 160-byte descriptor: 32-byte common header plus a 128-byte `RAW` or `DISSECTED` view.
2. Must `DISSECTED` also retain all first 128 raw bytes?
   - If yes, increase the descriptor size instead of overloading the view.
3. Which fields and maximum tunnel/IPv6-extension depth are mandatory in version 1?
4. May multiple CPUs claim the same packet, or is sharing only CPU plus host?
5. Is RX-to-TX zero-copy required across all queues and tenants?
6. What is the queue ordering rule: global ingress order, per flow, or per queue only?
7. What happens on RX exhaustion when pause/PFC is unavailable: tail drop, class drop or spill to host?
8. Which timestamps and accuracy are required: free-running device time, PTP, RX SFD or another boundary?

## Memory and performance

1. Is RX-RAM on-chip only, or may HBM/DDR be used?
2. Target RX-RAM capacity and per-stream TxFifo depth?
3. Is 2 KiB cell allocation acceptable, including chained jumbo packets?
4. What sustained processing-DMA fraction is expected in addition to host line rate?
5. Must every packet payload be processed by a CPU?
   - The proposed 256-bit L2 ports favor descriptor-first, selective payload access.
6. Is 512-bit processing RAM fabric acceptable for the 800G build while L2 adapters remain 256-bit?
7. What worst-case PCIe payload efficiency and safety margin must be guaranteed?

## CPU and software

1. RV32 or RV64 for the product CPU?
   - Current Tribe configuration is RV32 with four cores per shared L2.
2. Required boot memory, L2 size and per-cluster local RAM?
3. Bare-metal runtime, small RTOS or Linux?
4. Required inter-core and inter-cluster synchronization primitives?
5. Can one cluster be reset and upgraded while its queues migrate to another cluster?
6. What watchdog timeout and buffer-reclamation policy are acceptable?

## Protocol and offload scope

1. Which pause/PFC priorities and negotiation behavior are mandatory?
2. Which checksum, RSS, VLAN and tunnel features belong in fixed RTL version 1?
3. Which crypto algorithms, key counts and trust boundary are required?
4. Which TCP functions are required: checksum, segmentation, reassembly, connection state or full transport?
5. Which RoCEv2 and Ultra Ethernet protocol revisions/features are targets?
6. Is lossless behavior required end to end, or only within selected traffic classes?

## Host and security

1. Single physical function first, or SR-IOV from version 1?
2. Required host OS and driver model?
3. Are ATS/PASID/IOMMU features required?
4. Is peer-to-peer DMA required?
5. What firmware authentication, secure boot and key-storage requirements apply?
6. Which debug apertures are permitted in production?

## Suggested defaults until answered

- First timing target: 400G, one port, full duplex.
- `N=8` for functional and throughput integration; support the RTL parameter
  range `1..8`.
- 9 KiB maximum frame, 2 KiB RX cells, and eight packet-committed TxFifos.
- 160-byte descriptors and descriptor-first CPU decisions.
- Coherent burst-capable L2 DMA port; uncached local window only for bring-up.
- Keep the L2 traversal for firmware-selected traffic; add a direct
  packet-RAM-to-host DMA path for line-rate bulk capture.
- Single PCIe physical function before SR-IOV.
- RAW parsing fallback; unsupported packets are forwarded or dropped by policy, never corrupted.
