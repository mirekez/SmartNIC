# SmartNIC architecture

## Scope

- 400G and 800G full-duplex Ethernet SmartNIC SoC.
- RTL source: synthesizable cpphdl C++ dialect.
- Outputs: native C++ simulation and cpphdl-generated SystemVerilog.
- Verification: native C++ simulation, generated-SystemVerilog lint/Verilator
  tests, and native end-to-end firmware/traffic tests.
- PCS, SerDes and the PCIe PHY/controller hard block are outside the SoC RTL.
- First target: FPGA. ASIC and narrower/faster datapaths remain possible.

## Top level

```text
 Ethernet/PCS       SmartNIC        Processing          System          Host
 8 x 160/320b   +-------------+   +---------------+   +------------+  +------+
 <============>| Network     |-->| N x Tribe     |-->| 8 RX/TX    |=>| RAM  |
               | balance/RAM |<--| fetcher + DMA |<--| queues/DMA |  |driver|
               +-------------+   +---------------+   +------------+  +------+
                    net_clk       cpu_clk/l2_clk          sys_clk
```

## Levels

1. Network level
   - Terminates the MAC-side Ethernet data contract.
   - Balances frames over eight internal streams.
   - Parses RX headers and forms descriptors.
   - Stores packet contents in RX-RAM.
   - Accepts packet streams into eight packet-committed TxFifos.
   - Inserts requested TX fields and sends frames.
   - Owns packet accounting, flow control and wire-rate deadlines.

2. Processing level
   - Contains `N` Tribe CPU clusters.
   - Each cluster contains four RISC-V cores and one shared L2 cache.
   - L2 data width is 256 bits; the 400G target uses 312.5 MHz L2 and 1.25 GHz
     CPU cores to retain command and packet-boundary margin.
   - 800G remains parameterized but is outside the current sustained proof.
   - Exposes descriptor-prefetch and packet-DMA MMIO devices to every core.
   - Moves selected packet data between packet RAM, L2 caches and system level.

3. System level
   - Implements eight processing-to-host and eight host-to-processing queues.
   - Selects Avalon or AXI4 control/DMA ports with `HOST_AXI4`.
   - Implements 1024-entry RX/TX rings and one host `MasterDMA`.
   - A future attachment wrapper supplies PCIe protocol, interrupts and boot
     maintenance.
   - Exports descriptors, events and statistics to the host.

## Datapath

```text
RX capture:
 post-PCS -> balance -> RxRAM + descriptor CDC -> DescriptorFetcher
 RxRAM -> PacketDMA(DMA_NETWORK_CPU) -> coherent L2
 L2 -> PacketDMA(DMA_CPU_SYSTEM) -> CDC -> System RxQueue -> host DMA

TX paths:
 System TxQueue -> CDC -> PacketDMA(DMA_SYSTEM_CPU) -> coherent L2
 coherent L2 -> PacketDMA(DMA_CPU_NETWORK) -> CDC -> Network TxFifo
```

- Control and payload are separate after parsing.
- Descriptors use small queues; complete packets use banked packet RAM.
- A packet handle, not a raw RAM address, crosses level boundaries.
- Handle validation uses pool ID, buffer index and generation.
- RX buffers are reference-counted when both CPU and host own a packet.
- A TxFifo packet becomes visible only after EOP commits it and its storage is
  reclaimed as the output merger consumes it.

## Packet descriptor

- Fixed size: 160 bytes, five 256-bit beats.
- Common header: 32 bytes.
  - Format and version.
  - Packet handle and byte length.
  - Ingress/egress port and queue.
  - Timestamp or timestamp tag.
  - RSS/flow hash.
  - Parser status, checksum status, errors and ownership flags.
- Packet view: 128 bytes, padded with zeroes for short packets.
- Formats:
  - `RAW`: the first 128 packet bytes without reordering.
  - `DISSECTED`: a versioned 128-byte normalized parser result.
- The common header records truncation and parser depth.
- An RX descriptor references the full packet in RX-RAM. A transmitted packet
  is supplied in full through a TxFifo; there is no separate transmit RAM.
- Unknown protocols fall back to `RAW` and preserve the packet handle.

## Descriptor FIFOs

- Network descriptors cross into a per-cluster `DescriptorFetcher`.
- Each fetcher pre-reads up to four descriptors from the shared eight-stream
  source and presents one descriptor only to its assigned cluster.
- Each cluster has an eight-entry `PacketDMA` command queue.
- System contains exactly eight `RxQueue` and eight `TxQueue` instances.
- Rich claim/completion, programmable watermark and tenant semantics remain
  future work.

## Clock and reset domains

- `net_clk`: 312.5 MHz; MAC datapath and network-side packet streams.
- `l2_clk`: `312.5 MHz * NET_LANE_WIDTH / 256`; Tribe L2 boundary and
  Network/System CDC side.
- `cpu_clk`: currently `4 * l2_clk`; Tribe cores, primary memory interface,
  fetchers and packet DMA.
- `sys_clk`: 256 MHz in the shared harness; system queues, controller and host DMA.
- `mgmt_clk`: low-rate reset, MDIO and configuration.
- All domain crossings use asynchronous FIFOs, synchronizers or reset handshakes.
- Resets assert asynchronously and release synchronously within each domain.
- Queue pointers cross domains as Gray-coded values; payload RAM is never inferred as unsafe multi-clock logic.

## Performance rules

- 400G port: `8 * 160 * 312.5 MHz = 400 Gb/s` raw datapath capacity.
- 800G port: `8 * 320 * 312.5 MHz = 800 Gb/s` raw datapath capacity.
- One 400G processing lane is 256 bits x 312.5 MHz = 80 Gb/s gross; eight lanes
  provide 640 Gb/s gross aggregate capacity.
- Network ingress and egress receive deadline-reserved packet-RAM bandwidth.
- The current functional capture path traverses L2; a direct packet-RAM/host
  path is required before claiming sustained host line rate.
- CPU DMA is for headers, selected payloads and exceptional packets.
- No correctness requirement may depend on average packet size.
- Minimum-frame, back-to-back, simultaneous RX/TX and worst-case bank-conflict tests are mandatory.

## Build and verification contract

- Use the existing environment exported in `cpphdl/.conda`.
- Tool baseline from `cpphdl/requirements.yaml`:
  - Clang/LLVM 21.1.3.
  - CMake 3.26.4 and Make 4.4.1.
  - Verilator 5.034.
- Do not depend on the developer's system compiler or Verilator.
- Top-level build flow:

```text
conda activate ./cpphdl/.conda
cmake -S . -B build
cmake --build build
ctest --test-dir build
```

- Each synthesizable C++ block needs:
  - A native C++ unit test.
  - A generated-SystemVerilog lint/build target.
  - A Verilator equivalence or system test.
- `test/capture.cpp` covers RX, descriptor polling, two CPU DMA operations,
  System queueing and host-memory DMA with real Tribe firmware.
- The generated SmartNIC, Processing and System hierarchies are linted by
  Verilator; unit tests cover both native and Verilator flows.

## Verified capture system

- Eight Tribe clusters, four cores per cluster.
- RX-RAM uses 8,192 rows per sub-bank in the shared harness. Handles are 17
  bits, preserving equal byte capacity in 160-bit and 320-bit configurations.
- Only local hart 0 runs the capture loop; `mhartid` is wired from Tribe's
  boot hart ID.
- Functional capture injects 32 deterministic mixed-size frames with 12-byte
  IPG and samples eight to host; sustained mode injects 960 full-size frames
  and samples 96, with no source-side stalls.
- 400G: 117 aggregate input beats; all packets captured byte-for-byte.
- 800G: 59 aggregate input beats; all packets captured byte-for-byte.
- Balanced streams may complete in different global order. Validation is an
  order-independent unique packet permutation; ordering is preserved per queue.
- The harness preloads external DDR directly. System-controlled firmware load
  is not implemented yet.

## Current gaps and next work

1. Replace bounded monotonic RxRAM allocation with a reclaimable packet pool.
2. Complete MAC filtering/FCS, parser/dissector and TX field insertion.
3. Add direct RxRAM-to-host and host-to-network paths for line-rate host DMA.
4. Add DMA burst/outstanding support, interrupts, error completions and fences.
5. Add System firmware loading, boot control and recovery.
6. Bind a PCIe hard block and prove 400G/800G full-duplex bandwidth.
