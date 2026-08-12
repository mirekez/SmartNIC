# System level

## Responsibilities

- Adapt the portable SoC to PCIe or a later host attachment.
- Execute host-driver transfers.
- Execute CPU-originated system transfers.
- Load and supervise processing software.
- Export descriptors, statistics, completions and health.
- Isolate host functions, CPU clusters and packet queues.

## Current RTL

- `System<8,256>` contains eight `RxQueue` and eight `TxQueue` instances.
- `RxQueue[i]` carries packets from Processing to the host.
- `TxQueue[i]` carries packets from the host to Processing.
- Each direction has a 16-entry packet-aware asynchronous FIFO between
  `l2_clk` and `sys_clk` before the System queue.
- `HOST_AXI4` selects the external bus:
  - `0`: Avalon-MM control slave and host-memory master.
  - `1`: AXI4 control slave and host-memory master.
- The Controller implements 1024 RX and 1024 TX descriptors.
- One 512-bit, 256 MHz `MasterDMA` executes one host transfer at a time and
  packs/unpacks the 256-bit queue format.
- TX descriptors support scatter/gather; entries are combined until EOP.

## Sustained capture throughput test

- `run_capture_400_throughput` and `run_capture_800_throughput` inject 960
  consecutive 1516-byte packets with 12-byte IPG.
- The traffic source advances like a physical Ethernet link and asserts on the
  first cycle that SmartNIC deasserts ingress ready.
- The test reports balancer occupancy, RX descriptor FIFO occupancy, RxRAM
  completion occupancy, CPU prefetched descriptors and completed DMA commands.
- Capture firmware drains every packet from RxRAM through one of eight
  PacketDMAs and forwards every tenth packet directly to the matching System
  queue (96 of 960); unselected packets use the PacketDMA discard path.
- The targets are not registered in default CTest because the eight full CPU
  clusters make their C++ simulation intentionally long.
- Configure with `-DSMARTNIC_ENABLE_SUSTAINED_CAPTURE_TESTS=ON` to register
  them as deliberately strict performance gates.
- Eight 256-bit PacketDMA paths provide 800 Gb/s aggregate gross bandwidth at
  the 800G L2 clock.
- The 512-bit, 256 MHz host MasterDMA has a 131.072 Gb/s theoretical ceiling;
  one-in-ten capture keeps offered packet payload below that ceiling.
- Current measured results for 1516-byte packets and 12-byte IPG:
  - 800G: 960 packets in 4,584 uninterrupted network cycles, zero backpressure.
  - 400G: 960 packets in 9,168 uninterrupted network cycles, zero backpressure.
  - Every PacketDMA completes 120 packets; 96 sampled host packets are checked
    byte-for-byte.
- Full capture of every 800G packet still requires more host-DMA parallelism;
  the current test deliberately limits PCIe traffic to one packet in ten.

## Structure

```text
 Processing/l2_clk            System/sys_clk                    Host
 CPU -> Rx CDC -----------> RxQueue --+                     +---------+
 CPU <- Tx CDC <----------- TxQueue <-+-- Controller/DMA <=>| memory  |
                                      ^                     | driver  |
                                      +--- control slave ---+---------+
```

### Current packet paths

```text
Network -> CPU:
RxRAM -> PacketDMA(DMA_NETWORK_CPU) -> coherent L2

CPU -> host:
L2 -> PacketDMA(DMA_CPU_SYSTEM) -> Rx CDC -> RxQueue
   -> Controller -> MasterDMA -> posted host buffer

host -> CPU:
host buffer -> MasterDMA -> TxQueue -> Tx CDC
   -> PacketDMA(DMA_SYSTEM_CPU) -> coherent L2

CPU -> Network:
L2 -> PacketDMA(DMA_CPU_NETWORK) -> Network TxFifo
```

- Capture uses PacketDMA's direct RxRAM-to-System fast path for selected packets
  and discard path for the rest; ordinary DMA operations still exercise L2.
- Direct RxRAM-to-host and host-to-Network paths remain required for sustained
  400G/800G host traffic.

## Current ring registers

- Control/status: `0x0000`/`0x0004`.
- RX producer/consumer: `0x0010`/`0x0014`.
- TX producer/consumer: `0x0018`/`0x001c`.
- Completion count: `0x0020`.
- Per-queue status starts at `0x0100`, stride `0x20`.
- RX/TX descriptor storage starts at `0x10000`/`0x20000`.

## Planned host queue contract

- Host posts receive buffers and transmit work descriptors.
- The current Controller consumes RX/TX descriptors; richer event/error
  completion rings are planned.
- Queue state:
  - Base address and size.
  - Producer and consumer counters.
  - Function/tenant owner.
  - Interrupt vector, threshold and timer.
- Doorbells are posted writes; status reads are not required in the fast path.
- Descriptor formats are versioned and reported by capability registers.
- Queue reset/drain and interrupt coalescing remain future work.

## Current host DMA

- `MasterDMA` accepts Controller commands and transfers 512-bit host beats,
  packing or splitting the 256-bit packet-queue beats.
- Card-to-host consumes a selected RxQueue and writes the posted host address.
- Host-to-card reads one or more host fragments and emits one packet into the
  selected TxQueue.
- Both Avalon and AXI4 variants have unit tests.

## Planned line-rate host DMA engines

- Separate card-to-host and host-to-card engines.
- Multiple queue contexts and outstanding PCIe tags per engine.
- Scatter/gather and unaligned host buffers.
- Split requests at page, maximum-payload and maximum-read-request boundaries.
- Reassemble out-of-order completions by tag.
- Direct paths:
  - RX-RAM to host receive buffers.
  - Host transmit buffers directly into a selected TxFifo.
  - Descriptor/statistics blocks to host.
- The direct packet path does not enter an L2 cache.
- Reserve enough RX-RAM and TxFifo service to sustain the configured host line
  rate.

## CPU-originated system DMA

- CPU-originated data currently enters/leaves the corresponding System queue
  through `DMA_CPU_SYSTEM`/`DMA_SYSTEM_CPU` PacketDMA operations.
- The host driver posts a ring descriptor and Controller invokes MasterDMA.
- Direct CPU host-address commands, traffic classes, cookies, interrupts and
  reset completions are future extensions.

## CPU program loading and maintenance

The following is required product behavior but is not implemented in `System`
yet. The capture harness currently preloads each external DDR model directly.

- Hold a cluster in reset while loading its image.
- Load boot memory or cluster RAM through a bounded maintenance aperture.
- Program entry point, stack, queue map and capability block.
- Verify image length and optional digest/signature before release.
- Release cores in a defined order; secondary cores wait at a boot mailbox.
- Support warm restart of one cluster without resetting network or PCIe state.
- Watchdog actions: interrupt, halt, dump state, reset cluster and reclaim handles.
- Crash data includes PC/register summary, queue ownership and recent DMA completions.

## Statistics and descriptors

- Provide atomic snapshots of network, processing, DMA and PCIe counters.
- DMA large statistics blocks; do not require thousands of BAR reads.
- Allow selected RX descriptors to be mirrored or transferred to host queues.
- Preserve ingress sequence, timestamp and packet handle correlation.
- Rate-limit telemetry so it cannot starve packet traffic.

## Control plane

- Capability ROM identifies build, interfaces and feature versions.
- Shadow-and-commit registers update multiword network configuration.
- Privileged operations include reset, MDIO, firmware load and debug apertures.
- MSI-X supports queue, link, DMA error, watchdog and fatal-event vectors.
- Interrupt coalescing has packet threshold and timeout controls.

## Reliability and isolation

- Validate every DMA address and length before issue.
- Use IOMMU/PASID when available; otherwise use driver-pinned windows.
- Partition queues, packet pools and counters by function/tenant.
- Poison or zero buffers before crossing a security domain.
- Detect PCIe surprise-down and stop new DMA immediately.
- Preserve enough metadata to reclaim buffers after abort/reset.
- Fatal errors freeze a compact trace without blocking management access.

## Attach-point replacement

- Keep queue, DMA-command and packet-RAM interfaces independent of PCIe.
- A later wrapper may implement another coherent or streaming attachment.
- Replacement must preserve ordering, completion, isolation and bandwidth contracts.

## End-to-end capture test

- `test/SmartNICTest.h` composes SmartNIC, eight Processing clusters, System,
  external DDR models, a traffic source and an Avalon host-memory model.
- `test/capture.elf` polls every descriptor; every tenth local packet streams
  RxRAM-to-System and all others are drained through the discard fast path.
- The functional host test posts eight receive-ring entries and validates the
  selected packet bytes in both 400G and 800G builds. Sustained mode uses 960
  ingress packets and 96 host entries.
- The source offers traffic every Network clock and treats any `ready` stall as
  a wire-speed error.
