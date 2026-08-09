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

Each direction carries these signals:

```text
data [8][NET_LANE_W]
keep [8][NET_LANE_W/8]       one bit per valid byte
valid[8]
sop_valid[8]
sop_offset[8]                first byte of the new frame
eop_valid[8]
eop_offset[8]                last byte of the ending frame
error[8]
ready[8]                     internal/adaptor flow control
```

- Flattening `data[0]` through `data[7]` gives time-ordered bytes for the cycle.
- `data[0]` contains the earliest lane slice in a cycle.
- Bytes within a lane increase in time with increasing byte index.
- `keep` may contain a gap between an EOP and a later SOP.
- EOP and SOP may both be asserted in one lane and one clock.
- When both are asserted for different frames, `eop_offset < sop_offset`.
- A frame never changes logical stream after input balancing.
- RX error is sticky for the affected frame, is associated with its EOP and is copied to its descriptor.
- TX errors abort the affected frame and increment an error counter.
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

## System interface (PCIe)

### Boundary

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

### Transaction channels

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

### Data width

- Parameterized at 256, 512 or 1024 bits.
- Width is independent of packet-RAM and L2 width.
- `valid/ready`, byte enables, SOP/EOP and empty-byte count accompany every stream.
- Width adapters preserve PCIe tag ordering and do not serialize independent queues.

### BAR contract

- BAR0: version, capabilities, reset, health and interrupts.
- BAR2: queue doorbells and producer/consumer indices.
- BAR4 or an internal aperture: debug and bounded memory windows; optional.
- 64-bit registers use an explicit atomic snapshot or low/high commit rule.
- Capability registers report descriptor version, queue count, RAM size, `N`, clocks and feature bits.

### DMA contract

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
