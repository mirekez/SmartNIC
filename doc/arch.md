# SmartNIC architecture

## Scope

- 400G and 800G full-duplex Ethernet SmartNIC SoC.
- RTL source: synthesizable cpphdl C++ dialect.
- Outputs: native C++ simulation and cpphdl-generated SystemVerilog.
- System tests: generated SystemVerilog under Verilator.
- PCS, SerDes and the PCIe PHY/controller hard block are outside the SoC RTL.
- First target: FPGA. ASIC and narrower/faster datapaths remain possible.

## Top level

```text
 Ethernet/PCS side                 SmartNIC SoC                       Host
 8 x 160/320b              +-------------------------+          +-----------+
 <========================>| network                 |          | driver    |
                           | MAC, parse, packet RAM   |          | queues    |
                           +------------+------------+          +-----+-----+
                                        | descriptors / DMA           |
                           +------------+------------+                PCIe
                           | processing              |                 |
                           | N x Tribe(4 cores + L2) |                 |
                           +------------+------------+                 |
                                        | commands / status           |
                           +------------+------------+                 |
                           | system                  |<================+
                           | host DMA, BAR, control  |
                           +-------------------------+
```

## Levels

1. Network level
   - Terminates the MAC-side Ethernet data contract.
   - Balances frames over eight internal streams.
   - Parses RX headers and forms descriptors.
   - Stores packet contents in RX-RAM.
   - Reads packet contents from the smaller TX-RAM.
   - Inserts requested TX fields and sends frames.
   - Owns packet accounting, flow control and wire-rate deadlines.

2. Processing level
   - Contains `N` Tribe CPU clusters.
   - Each cluster contains four RISC-V cores and one shared L2 cache.
   - L2 data width is 256 bits; target clock is 400 MHz.
   - Exposes RX-QUEUE, TX-QUEUE and CMD-FIFO devices to every core.
   - Moves selected packet data between packet RAM, L2 caches and system level.

3. System level
   - Terminates a vendor-neutral PCIe transaction interface.
   - Implements BAR control, interrupts and host-visible queues.
   - Runs direct host DMA independently of CPU packet DMA.
   - Loads CPU programs, controls boot/reset and monitors health.
   - Exports descriptors, events and statistics to the host.

## Datapath

```text
RX: MAC -> balance -> parse -> CDC -> RX-RAM -> process or host
                         +-------> RX-QUEUE -> CPU decision

TX: host or CPU -> TX-RAM -> CDC -> insert -> schedule -> MAC
                      CPU -> TX-QUEUE -----------+
```

- Control and payload are separate after parsing.
- Descriptors use small queues; complete packets use banked packet RAM.
- A packet handle, not a raw RAM address, crosses level boundaries.
- Handle validation uses pool ID, buffer index and generation.
- RX buffers are reference-counted when both CPU and host own a packet.
- TX buffers return to their free list only after MAC completion or discard.

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
- The full packet remains in RX-RAM or TX-RAM; a descriptor never replaces it.
- Unknown protocols fall back to `RAW` and preserve the packet handle.

## Descriptor queues

- RX-QUEUE
  - Producer: network level.
  - Consumers: CPU clusters and, when configured, system DMA.
  - Operations: `PEEK`, atomic `CLAIM`, `COMPLETE`, `DROP`.
- TX-QUEUE
  - Producers: CPU clusters and system level.
  - Consumer: network level.
  - Operations: `RESERVE`, `WRITE`, ordered `COMMIT`, `CANCEL`.
- Completion queues return status and release ownership.
- Each queue has programmable depth, watermarks, interrupt threshold and timer.
- Queue IDs provide traffic-class and tenant isolation.
- Queue state uses monotonic producer/consumer counters; wrapped indices are not ownership tokens.

## Clock and reset domains

- `net_clk`: 312.5 MHz; MAC datapath and network-side packet streams.
- `proc_clk`: 400 MHz; packet RAM fabric, DMA and Tribe L2 interfaces.
- `sys_clk`: selected by the PCIe hard block; system DMA and PCIe transaction logic.
- `mgmt_clk`: low-rate reset, MDIO and configuration.
- All domain crossings use asynchronous FIFOs, synchronizers or reset handshakes.
- Resets assert asynchronously and release synchronously within each domain.
- Queue pointers cross domains as Gray-coded values; payload RAM is never inferred as unsafe multi-clock logic.

## Performance rules

- 400G port: `8 * 160 * 312.5 MHz = 400 Gb/s` raw datapath capacity.
- 800G port: `8 * 320 * 312.5 MHz = 800 Gb/s` raw datapath capacity.
- One processing lane: `256 * 400 MHz = 102.4 Gb/s` theoretical.
- 800G width conversion has only 2.4% raw clock-rate margin per lane.
- Network ingress and egress receive deadline-reserved packet-RAM bandwidth.
- Host line-rate transfer bypasses L2 caches and processing DMA.
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
- Required top-level build flow after the RTL/CMake scaffold is added:

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
- End-to-end tests cover RX, CPU decision, host DMA, TX and reset recovery.

## Initial implementation order

1. Define stream, descriptor, queue and packet-handle types.
2. Implement native C++ models for packet RAM, FIFOs and scoreboards.
3. Implement 400G balancing, CDC and lossless RX/TX loopback.
4. Add RAW descriptors and queue devices.
5. Integrate one four-core Tribe cluster and its coherent L2 DMA port.
6. Add parser/dissector and TX field insertion.
7. Add scalable `N` clusters and processing DMA scheduling.
8. Add the vendor-neutral system interface and host DMA model.
9. Bind an FPGA PCIe hard block and close 800G timing/bandwidth.
