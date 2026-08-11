# Processing level

## CPU subsystem

- Parameter `N`: number of Tribe CPU clusters.
- One cluster:
  - Four RISC-V cores (`CPUS_PER_L2_CACHE=4`).
  - Private L1 caches.
  - One shared L2 cache.
  - 256-bit L2 memory/DMA datapath.
- The L2 boundary clock is derived from the selected network lane rate:
  - 195.3125 MHz for 160-bit network lanes.
  - 390.625 MHz for 320-bit network lanes.
- `cpu_clk` is currently four times `l2_clk`. Cores, MMIO devices, PacketDMA
  control and the exported primary DDR AXI interface use `cpu_clk`.
- Each cluster has independent boot, reset, fault and performance state.
- Interrupts identify queue, DMA completion, timer, system request and fault sources.

```text
            +---------------- cluster i ----------------+
Rx/TxFifo   | core0 core1 core2 core3 -> shared L2      |
devices --->|                         <-> DMA slave port  |
            +--------------------------------------------+
```

## Current MMIO devices

- Every cluster owns one `DescriptorFetcher<4>` and one `PacketDMA<8>`.
- Both devices are in Tribe's uncached IOMEM region:
  - Fetcher: `0x40000000 + 0x0000`.
  - PacketDMA: `0x40000000 + 0x1000`.
- A fetcher pre-reads descriptors assigned to that cluster from the eight
  Network descriptor streams.
- Software can enable prefetch, poll availability, read the full five-word
  descriptor or selected fields, then pop/skip it.
- A descriptor is visible only to its assigned cluster. The current dispatcher
  uses round robin; hashing can replace that policy later.
- PacketDMA accepts up to eight queued commands and reports ready, busy,
  completion and a typed protocol-error reason.
- Blocking operations and interrupt delivery are future work; current firmware polls.

## Processing DMA

### Current model

- Processing instantiates one independent PacketDMA per cluster.
- Each PacketDMA connects to one coherent 256-bit Tribe L2 DMA port, one RxRAM
  read port, one Network TX stream, one System RxQueue and one System TxQueue.
- Commands execute in FIFO order within a cluster; clusters operate independently.
- Four operations are implemented:
  - `DMA_SYSTEM_CPU`: System TxQueue to coherent L2.
  - `DMA_CPU_SYSTEM`: coherent L2 to System RxQueue.
  - `DMA_CPU_NETWORK`: coherent L2 to Network TxFifo.
  - `DMA_NETWORK_CPU`: Network RxRAM to coherent L2.

```text
 cluster 0 cores -> PacketDMA[0] <-> L2[0] <-> RxRAM/Network/System queue 0
 cluster 1 cores -> PacketDMA[1] <-> L2[1] <-> RxRAM/Network/System queue 1
 ...
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
- Each cluster's general DDR AXI master is exported from `Processing`; external
  RAM or a DDR controller is attached outside the module.
- Tribe already crosses between its L2 side and primary CPU/memory side. The
  exported DDR model is therefore clocked by `cpu_clk`, not `l2_clk`.

### Command

- Fixed and naturally aligned MMIO command record.
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

- Current PacketDMA preserves command FIFO order per cluster and transfers one
  command at a time.
- Future scalable scheduling should:
  - Use per-cluster and per-memory-bank request queues.
  - Use weighted deficit round robin across clusters.
  - Age requests to prevent starvation.
  - Split long copies into bounded bursts so descriptor/header traffic stays responsive.
  - Track read and write credits independently.
  - Return completion only after the destination is visible in its coherency domain.

## CPU integration

- `rtl/processing/CPU.h` wraps Tribe, its four cores, L1 caches, shared L2 and
  the minimum MMIO/external-memory connections.
- `boot_hartid_in` is propagated into Tribe CSR `mhartid` (`0xF14`).
- The capture firmware lets only `(mhartid & 3) == 0` run, preventing four
  local harts from consuming the same fetcher/DMA command stream.
- The shared harness instantiates `N=4`; the RTL supports `1 <= N <= 8`.

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

- One 256-bit lane peaks at 50 Gb/s in a 400G build or 100 Gb/s in an 800G build.
- A single lane is insufficient for either 400G or 800G full-payload movement.
- Eight ideal lanes equal the port rate; at 85% sustained efficiency, either
  port width requires ten active 256-bit lanes for full-payload movement.
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
