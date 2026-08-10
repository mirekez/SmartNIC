# Processing level

## CPU subsystem

- Parameter `N`: number of Tribe CPU clusters.
- One cluster:
  - Four RISC-V cores (`CPUS_PER_L2_CACHE=4`).
  - Private L1 caches.
  - One shared L2 cache.
  - 256-bit L2 memory/DMA datapath.
- Target processing clock: 400 MHz.
- Each cluster has independent boot, reset, fault and performance state.
- Interrupts identify queue, DMA completion, timer, system request and fault sources.

```text
            +---------------- cluster i ----------------+
Rx/TxFifo   | core0 core1 core2 core3 -> shared L2      |
devices --->|                         <-> DMA slave port  |
            +--------------------------------------------+
```

## FIFO devices

- RxFifo, TxFifo, CMD-FIFO and SYSTEM-REQ-FIFO are memory-mapped special devices.
- Any core in any cluster may access an allowed FIFO.
- Access control maps FIFO IDs to cluster/core or tenant.
- RX operations:
  - Read availability without consuming.
  - Atomically claim one descriptor.
  - Read five 256-bit descriptor beats.
  - Complete with forward, drop, retain or error status.
- TX operations:
  - Reserve a slot.
  - Write descriptor beats.
  - Commit atomically after all fields and payload writes are visible.
- Blocking operations use wait/interrupt; polling operations never lock the interconnect.
- FIFO devices expose overflow, underflow and malformed-operation counters.
- SYSTEM-REQ-FIFO delivers bounded host/system work to a selected cluster.
- A core answers a system request with a normal completion and, when data must move, a `HOST` DMA command.

## Processing DMA

### Model

- One logical DMA master owns command ordering, validation and completion.
- It contains `N` independently schedulable 256-bit cache adapters.
- It presents `N` logical read/write ports to RX-RAM and eight packet-stream
  write paths to the TxFifos.
- It may also route a flagged command to the system-level DMA service.
- A command names source and destination spaces; it does not expose physical RAM-bank wiring.

```text
 cores -> CMD-FIFO -> validate -> scheduler
                              +-> lane 0 <-> L2[0] <-> packet RAM
                              +-> lane 1 <-> L2[1] <-> packet RAM
                              ...
                              +-> lane N <-> L2[N] <-> packet RAM
                              +-> HOST flag -> SYSTEM-DMA-REQ-FIFO
```

### L2 attachment

- Use the Tribe L2 external coherent AXI slave path as the target attachment.
- DMA writes must invalidate/update matching cache lines before completion.
- DMA reads must observe dirty L2 data.
- The current L2 external path is a useful functional baseline but needs:
  - Burst transfers of complete 32-byte cache lines.
  - Multiple outstanding IDs.
  - Backpressure-safe AW/W handling.
  - Fair arbitration between cores and DMA.
  - Per-source completion and error reporting.
- First fallback: a reserved uncached local-memory window per cluster.
- Software must not alias cached and uncached mappings of the same buffer.

### Command

- Fixed, versioned and naturally aligned CMD-FIFO record.
- Fields:
  - Opcode and flags.
  - Source/destination space: RX-RAM, a selected TxFifo, L2 cluster,
    system/host.
  - Packet handle or local address.
  - Cluster ID and L2 address.
  - Byte length and optional stride.
  - Queue/function/security domain.
  - Completion cookie.
- Flags include interrupt, fence, checksum assist and `HOST` routing.
- Invalid length, range, ownership or generation completes with an error and performs no transfer.

### Scheduling

- Preserve order only where commands request a fence or share an ordered queue.
- Use per-cluster and per-memory-bank request queues.
- Use weighted deficit round robin across clusters.
- Age requests to prevent starvation.
- Split long copies into bounded bursts so descriptor/header traffic stays responsive.
- Track read and write credits independently.
- Return completion only after the destination is visible in its coherency domain.

## Recommended RAM/L2/host attachment

### Functions

1. Packet-RAM bank fabric
   - Converts `N` logical DMA ports into queued requests to physical banks.
   - Hashes consecutive 32-byte words across sub-banks within the selected home bank group.
   - Separates request, write-data and response queues.

2. Per-L2 DMA adapter
   - Connects one scheduler lane to one cluster's coherent L2 slave port.
   - Aligns transfers to 32-byte cache lines.
   - Merges first/last byte masks.
   - Tracks IDs, faults and completions.

3. Central command scheduler
   - Validates ownership and address ranges.
   - Dispatches independent commands in parallel.
   - Enforces fences without globally serializing unrelated clusters.

4. Direct system DMA path
   - Connects host DMA directly to RX-RAM and the eight TxFifo write ports.
   - Never routes line-rate host traffic through a Tribe L2.
   - Accepts CPU-originated host commands through a small request/completion FIFO.

5. QoS controller
   - Gives wire-side RAM operations deadline priority.
   - Reserves a configured share for host DMA.
   - Uses remaining slots for processing DMA and debug.

### Requirements

- One 256-bit lane at 400 MHz peaks at 102.4 Gb/s before arbitration overhead.
- A single lane is insufficient for either 400G or 800G full-payload movement.
- At 85% sustained efficiency, full-payload processing would require at least:
  - Five active 256-bit lanes for 400G in one direction.
  - Ten active 256-bit lanes for 800G in one direction.
- Therefore the normal path sends only descriptors and selected packet regions to L2.
- Dedicated system DMA must sustain host line rate without consuming L2 bandwidth.
- RX-RAM must concurrently support:
  - RX wire writes.
  - Direct host reads at the configured host rate.
  - Reserved processing traffic and metadata operations.
- TxFifos buffer complete egress packets independently of RX-RAM, so transmit
  traffic cannot consume RX packet-memory bandwidth.
- Bank arbitration must meet bounded network latency, not only average throughput.
- Data movers require end-to-end ECC/parity status where the selected FPGA memories support it.
- Performance counters must expose useful bytes, bubbles, bank conflicts, queue waits and cache stalls.
- A synthesizable traffic generator must prove minimum-frame full-duplex operation.

## CPU decisions

- A core normally reads the descriptor first.
- It may decide without reading packet payload.
- It requests DMA of only the bytes needed by slow-path or offload code.
- Results include:
  - Drop.
  - Forward to a network queue.
  - Send to host.
  - Modify and forward.
  - Retain for multi-step processing.
- A watchdog reclaims descriptors and buffers abandoned by failed software.
