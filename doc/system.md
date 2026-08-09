# System level

## Responsibilities

- Adapt the portable SoC to PCIe or a later host attachment.
- Execute host-driver transfers.
- Execute CPU-originated system transfers.
- Load and supervise processing software.
- Export descriptors, statistics, completions and health.
- Isolate host functions, CPU clusters and packet queues.

## Structure

```text
                    +----------------------+
PCIe requests ----->| BAR / queue manager  |----> control and doorbells
                    +----------+-----------+
                               |
 host memory <======> host DMA engines <======> RX-RAM / TX-RAM
                               ^
                     CPU system-request FIFO
```

## Host queues

- Host posts receive buffers and transmit work descriptors.
- Card posts RX, TX, event and error completions.
- Queue state:
  - Base address and size.
  - Producer and consumer counters.
  - Function/tenant owner.
  - Interrupt vector, threshold and timer.
- Doorbells are posted writes; status reads are not required in the fast path.
- Descriptor formats are versioned and reported by capability registers.
- Queue reset drains or errors all owned packet handles deterministically.

## Host DMA engines

- Separate card-to-host and host-to-card engines.
- Multiple queue contexts and outstanding PCIe tags per engine.
- Scatter/gather and unaligned host buffers.
- Split requests at page, maximum-payload and maximum-read-request boundaries.
- Reassemble out-of-order completions by tag.
- Direct paths:
  - RX-RAM to host receive buffers.
  - Host transmit buffers to TX-RAM.
  - Descriptor/statistics blocks to host.
- The direct packet path does not enter an L2 cache.
- Reserve enough packet-RAM service to sustain the configured host line rate.

## CPU-originated system DMA

- Host work that requires firmware policy enters a per-cluster SYSTEM-REQ-FIFO and raises an interrupt.
- A processing command with `HOST` set enters the SYSTEM-DMA-REQ-FIFO.
- System level validates function, address window, packet ownership and length.
- Accepted commands share host DMA engines through a configured traffic class.
- Host-driver traffic and CPU traffic have separate credits and accounting.
- Completion returns to the originating cluster with cookie, byte count and status.
- A system reset completes outstanding CPU commands with an explicit reset error.

## CPU program loading and maintenance

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
