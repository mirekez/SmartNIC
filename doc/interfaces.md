# SoC interfaces

## Network side interface

### Scope

- Interface point: MAC client side of an external or vendor PCS.
- PCS, FEC, lane alignment, gearbox and SerDes are out of scope.
- Clock: 312.5 MHz.
- Lanes: 8.
- Parameter `NET_LANE_W`:
  - 160 bits for 400G.
  - 320 bits for 800G FPGA use.
  - A later implementation may use half width at twice the clock.
- Payload byte order and lane striping are fixed by one versioned adapter contract.

### RX/TX stream

The current SmartNIC top carries one aggregate handshake per direction:

```text
valid                         aggregate beat is present
data [8 * NET_LANE_W]         eight packed lane words
keep [8 * NET_LANE_W/8]       one bit per valid byte
sop  [8 * NET_LANE_W/8]       one bit at each frame's first byte
eop  [8 * NET_LANE_W/8]       one bit at each frame's last byte
ready                         aggregate beat was accepted
```

- RX additionally carries `raw`, used to select RAW descriptor formatting.
- Flattening lane 0 through lane 7 gives time-ordered bytes for the cycle.
- `data[0]` contains the earliest lane slice in a cycle.
- Bytes within a lane increase in time with increasing byte index.
- `keep` may contain a gap between an EOP and a later SOP.
- EOP and SOP may both be asserted anywhere in one aggregate clock.
- Multiple short frames and boundaries may occur in one aggregate beat.
- A frame never changes logical stream after input balancing.
- The adapter must absorb protocol-specific idles; the SoC sees bytes and frame boundaries.

```text
cycle n:   [ old frame ........ EOP ][ gap ][ SOP new frame .... ]
keep:      [ 1 1 1 1 1 1 1 1 1 1 ][ 0 0 ][ 1 1 1 1 1 1 1 1 ]
```

### Management

```text
mdc_out
mdio_out
mdio_oe
mdio_in
phy_irq_in
link_up_in
```

- MDIO supports Clause 22 and Clause 45 transactions through a host-visible controller.
- MDC division, preamble suppression, PHY address and timeouts are programmable.
- MDIO is a management path; it is not part of the packet clock domain.

### Negotiation and backpressure

- Adapter status reports link rate, duplex, FEC status and fault state.
- Internal `ready` may stop an FPGA adapter that supports backpressure.
- A real Ethernet link cannot be stopped immediately.
- RX-RAM watermarks request pause/PFC generation before buffers exhaust.
- Unsupported or disabled flow control ends in a configured drop policy with accounting.
- XGMII `/I/` characters represent available inter-packet idle budget.
- A PCS-side `valid` pause is legal only between frames and models a stopped
  abstract transfer/rate adapter; it must never interrupt a frame.  A
  continuous wire-side implementation fills that interval with legal idles.
- PAUSE and PFC negotiation are MAC control frames, distinct from deasserting
  the local PCS transfer-valid signal.
- Clause 46/81 deficit-idle accounting may remove at most three idles from a
  nominal 12-octet transmit gap.  The 8-idle pattern used by the integration
  test is an RX robustness case, not the SmartNIC transmit contract.

### Processing-side network boundary

- Clock: 312.5 MHz for the 400G target. The 800G parameter remains 390.625 MHz
  and is outside the current sustained-throughput claim.
- RX descriptor stream: 256-bit `valid/ready`, five words, word index, SOP/EOP.
- RxRAM read command per port: packet handle plus exact byte length.
- RxRAM response per port: 256-bit data, byte keep, SOP/EOP, `valid/ready`.
- TX: eight independent 256-bit data/keep/SOP/EOP `valid/ready` streams.
- All crossings use packet-aware Gray-pointer asynchronous FIFOs even though
  the nominal clocks are frequency-related; their phase and reset release are
  not assumed synchronous.

## System interface (PCIe)

### Current portable RTL boundary

- `System<8, 256>` contains eight processing-facing queue pairs.
- Each processing stream is 256-bit `data/keep/sop/eop/valid/ready`.
- `RxQueue[i]`: Processing to host.
- `TxQueue[i]`: host to Processing.
- A 16-entry asynchronous FIFO in each direction crosses `l2_clk`/`sys_clk`
  before the corresponding System queue.
- `HOST_AXI4=0` selects Avalon-MM ports; `HOST_AXI4=1` selects AXI4 ports.
- Avalon uses one target-oriented `AvalonIf` type for both sides. An interface
  instance ending in `_out` is automatically direction-reversed by cpphdl;
  `host_control` is target-facing and `host_dma_out` is master-facing.
- Control/slave port: 32-bit address, 512-bit data at 256 MHz.
- Host-memory/master port: 64-bit address, 512-bit data at 256 MHz.
- `MasterDMA` packs two 256-bit Processing queue beats into one host beat and
  splits host reads back into two queue beats.

```text
Processing        clock crossing       System             host model/wrapper
Rx stream ------> L2ToSystem FIFO ---> RxQueue --+-----> MasterDMA
Tx stream <------ SystemToL2 FIFO <--- TxQueue <-+<----- MasterDMA
                                                  ^
host control -------------------------------- Controller
```

### Controller register and ring contract

- Control/status registers: `0x0000`/`0x0004`.
- RX producer/consumer: `0x0010`/`0x0014`.
- TX producer/consumer: `0x0018`/`0x001c`.
- Completion counter: `0x0020`.
- Per-queue status window: `0x0100`, stride `0x20`.
- RX descriptor ring: 1024 entries at controller byte address `0x10000`.
- TX descriptor ring: 1024 entries at controller byte address `0x20000`.
- Descriptor size: 16 bytes.
  - 64-bit host address.
  - 16-bit byte length.
  - 8-bit queue ID.
  - 8-bit flags.
  - 32-bit reserved field.
- The RX ring supplies host destinations for card-to-host queue data.
- The TX ring supplies host sources for host-to-card queue data.
- TX scatter/gather chains entries until `SYSTEM_TX_DESCRIPTOR_EOP`.
- The shared harness provides an Avalon driver master, an Avalon DMA slave and
  4 MiB of byte-addressable host memory.

### Future PCIe wrapper

- The SoC uses a vendor-neutral transaction interface.
- The FPGA wrapper adapts it to the selected PCIe hard block.
- PCIe PHY, LTSSM, data-link retry and electrical lanes remain outside portable cpphdl RTL.

```text
 PCIe hard block             portable SmartNIC system level
+----------------+          +------------------------------+
| request stream |--------->| BAR decoder / host DMA       |
| completion     |<---------| tag and completion manager   |
| MSI-X          |<---------| interrupt coalescer          |
+----------------+          +------------------------------+
```

### Planned transaction channels

- Host-to-card requests:
  - Posted memory writes.
  - Non-posted memory reads.
  - BAR number, address, byte enables, requester ID, tag and attributes.
- Card-to-host requests:
  - DMA memory reads and writes.
  - Queue/PASID, address, length, tag and attributes.
- Completions:
  - Data, byte count, lower address, tag and status.
- Interrupts:
  - MSI-X vector request, function and acknowledgement.
- Link/configuration:
  - Link up, negotiated width/rate, function reset and fatal/non-fatal errors.

### Planned PCIe data width

- Parameterized at 256, 512 or 1024 bits.
- Width is independent of packet-RAM and L2 width.
- `valid/ready`, byte enables, SOP/EOP and empty-byte count accompany every stream.
- Width adapters preserve PCIe tag ordering and do not serialize independent queues.

### Planned BAR contract

- BAR0: version, capabilities, reset, health and interrupts.
- BAR2: queue doorbells and producer/consumer indices.
- BAR4 or an internal aperture: debug and bounded memory windows; optional.
- 64-bit registers use an explicit atomic snapshot or low/high commit rule.
- Capability registers report descriptor version, queue count, RAM size, `N`, clocks and feature bits.

### Planned DMA contract

- Scatter/gather queues use host physical or IOMMU-translated addresses.
- Separate engines serve host-to-card and card-to-host traffic.
- Queue IDs preserve ordering only within a queue.
- Requests may complete out of order across tags and queues.
- Maximum payload/read-request size comes from negotiated PCIe configuration.
- Payload targets, excluding protocol overhead:
  - At least 50 GB/s per direction for one 400G host path.
  - At least 100 GB/s per direction for one 800G host path.
  - Add implementation margin; do not select a PCIe configuration from raw signaling rate alone.
- Candidate attachment classes:
  - 400G: PCIe 5.0 x16 or any interface proving at least 50 GB/s useful payload per direction.
  - 800G: PCIe 6.0 x16 or multiple links proving at least 100 GB/s useful payload per direction.
- The candidate class is not acceptance evidence; measured worst-case payload throughput is.
- Errors produce a completion record and never silently release a live packet buffer.

### Optional later features

- SR-IOV functions and per-function queues.
- PASID, ATS and PRI.
- Peer-to-peer DMA.
- CXL.io-compatible attachment through a different system wrapper.
