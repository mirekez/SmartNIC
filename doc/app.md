# Applications

## Common deployment

- Host loads and starts one program per Tribe cluster.
- Host assigns Rx/TxFifos and policy tables.
- Network level produces RX descriptors continuously.
- CPU software makes a decision from the descriptor when possible.
- Payload DMA is requested only for data needed by the algorithm.
- Host receives selected packets, flow records or completions.

## Implemented capture application

- `test/capture.elf` is the first complete firmware workload.
- One hart per four-core Tribe cluster enables its `DescriptorFetcher` and
  polls for descriptors.
- For every descriptor it issues:
  1. `DMA_NETWORK_CPU`: packet bytes from the assigned RxRAM port to coherent
     L2 at local address `0x10000`.
  2. `DMA_CPU_SYSTEM`: the same bytes from L2 to the corresponding System
     `RxQueue`.
  3. Descriptor pop, then repeat.
- The host posts 32 receive buffers across the eight Controller RX queues.
- Controller and MasterDMA drain the queues into host memory.

```text
post-PCS traffic -> Network/RxRAM -> descriptor -> capture firmware
 -> coherent L2 -> System RxQueue -> host ring buffer
```

- The test mixes 64, 128, 256, 300, 512, 768, 1024 and 1516-byte frames.
- It runs with a 12-byte IPG and fails if the aggregate Network input stalls.
- Both 400G and 800G configurations capture all 32 packets byte-for-byte.
- Input balancing permits independent streams to complete out of global order.
  Applications needing ordering must select a per-queue/per-flow rule; the
  capture checker matches unique packets independent of global completion order.

## 1. Packet analysis and flow steering

### Functions

- Parse L2/L3/L4 and tunnel keys.
- Maintain short-lived per-flow state in cluster-local memory.
- Emit compact flow-accounting records to host queues.
- Apply host-installed flow commands.
- Direct traffic:
  - Network port/queue to network port/queue.
  - Network to host.
  - Host to network.
  - Drop or mirror.
- Sample packets or copy a bounded payload prefix for analysis.

### Fast path

```text
RX descriptor -> flow lookup -> action -> TX descriptor
                         +-----> compact host record
```

- A cache hit should require no full-packet copy into L2.
- Forwarding reuses the RX buffer when ownership and TX timing permit.
- Host rule updates use versioned tables and atomic generation changes.
- Unknown or exceptional flows enter a bounded slow-path queue.

### Outputs

- Flow key/hash and counters.
- First/last timestamp.
- TCP flags or protocol summary.
- Action and drop reason.
- Optional packet handle or sampled bytes.

## 2. RX/TX protocol offload

### Candidate offloads

- Cryptographic record or packet processing.
- TCP segmentation, reassembly and checksum processing.
- RoCEv2 transport processing.
- Ultra Ethernet transport processing.
- Tunnel encapsulation/decapsulation.

### Partition

- Fixed hardware:
  - Framing, bounded parsing, checksums, queues and packet RAM.
  - Optional crypto or checksum accelerators after their interfaces stabilize.
- Tribe software:
  - Connection state, policy, exceptions and protocol evolution.
- Host software:
  - Resource provisioning, keys/policies, recovery and application API.

### Data movement

- Descriptor-only decision is preferred.
- DMA only the required header, crypto block or payload range into a cluster.
- Long payload transforms use streaming accelerators or multiple DMA lanes.
- Completed packets are streamed into one of the eight TxFifos and become
  eligible for transmission only when EOP commits the complete packet.
- Keys and tenant state never appear in host-visible debug apertures.

### Correctness requirements

- Per-flow ordering is explicit.
- Retries and duplicate commands are idempotent or detected.
- Partial packets time out and release buffers.
- Checksums, authentication failures and sequence errors have distinct status.
- Software upgrade can drain one queue/cluster while others continue.

## Performance measurements

- Packets/s at minimum and mixed sizes.
- Useful Gb/s per direction and full duplex.
- Descriptor-decision latency percentiles.
- Bytes copied into L2 per packet.
- Packet-RAM bank conflicts and DMA efficiency.
- Host record/completion rate.
- Flow-table hit rate and slow-path rate.
