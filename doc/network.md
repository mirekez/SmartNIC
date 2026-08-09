# Network level

## Scope

- Own all wire-rate RX/TX operations.
- PCS, FEC and SerDes are outside this level.
- Run the external datapath at 312.5 MHz.
- Run packet RAM and processing-side ports at 400 MHz.
- Never depend on CPUs responding before an Ethernet deadline.

## Input balancing

### Function

- Convert one framed `8 x 160/320` input into eight independent `160/320` framed streams.
- Scan the flattened `8 x 160/320` cycle in byte-time order.
- Assign a new frame to an eligible output stream by round robin.
- Keep all bytes of a frame on its assigned stream.
- Skip stopped or over-watermark output streams.
- Preserve frame order in a separately recorded ingress sequence number.
- Allow a frame to stop and another frame to start in the same output clock.

```text
             +--------------------+     +-----------------+
8 wide lanes | boundary scan + RR |---->| banked transpose|--> stream 0
============>| frame destination  |     | elastic buffer  |--> stream 1
             +--------------------+     |                 |      ...
                                        +-----------------+--> stream 7
```

### State

- Current output owner for every active input frame.
- Next round-robin output.
- Per-output queued-byte credit and high watermark.
- At most two frame context updates per lane per cycle: one EOP and one SOP.
- A banked transpose buffer accepts all eight input lane words per cycle.
- Per-output packers drain at most one `160/320`-bit word per cycle.
- Small output skid buffers break ready paths and absorb read-bank conflicts.

### Rules

- SOP allocates exactly one output and one RX packet handle.
- Middle beats reuse the saved output.
- EOP closes the handle and advances the round-robin pointer.
- EOP+SOP closes the old context before allocating the new context.
- Round robin is byte-credit qualified: an output without room for one maximum frame is skipped.
- A malformed nested SOP, orphan EOP or illegal byte mask aborts only that frame.
- No output may receive bytes from two input frames in the same byte position.
- Backpressure is credit-based; combinational `ready` does not cross the balancer.
- The transpose buffer must absorb an aggregate-width frame arriving eight times faster than one output drains it.
- Capacity must cover maximum-frame skew plus CDC and bank-conflict margin.

### Verification

- All boundary offsets, including EOP at byte 0 and SOP at the last byte.
- EOP+SOP in one cycle with and without an idle-byte gap.
- Back-to-back minimum frames.
- Adversarial alternating minimum/jumbo frames; packet-count round robin alone must not overflow one output.
- One blocked output while the other seven continue.
- Round-robin fairness and wrap.
- 400G and 800G parameterizations.

## MAC

### RX

- Check preamble/SFD as required by the selected PCS adapter contract.
- Remove preamble and FCS from the packet stored in RX-RAM.
- Check FCS and length; record errors in the descriptor.
- Recognize unicast, multicast, broadcast and promiscuous modes.
- Apply station-address, VLAN and programmable policy filters.
- Timestamp the configured RX boundary.

### TX

- Enforce minimum frame size and inter-packet gap.
- Add padding and FCS.
- Insert a timestamp when requested.
- Schedule traffic classes without splitting a frame.
- Report transmitted, dropped and errored completions.

### Host-tunable parameters

- Primary and additional 48-bit Ethernet station addresses.
- IPv4 address/mask table.
- IPv6 address/prefix table.
- VLAN allowlist and default VLAN.
- Promiscuous, multicast and broadcast enables.
- MTU, pause/PFC policy and traffic-class mapping.
- Parser enables and checksum policy for IPv4 and IPv6.
- RX hash key and indirection table.
- Changes use shadow registers plus an atomic commit at a frame boundary.

The IP address tables are consumed by filtering, parsing and offload logic. They do not change basic Ethernet framing.

### MDIO

- Provide a host-visible Clause 22/45 command FIFO.
- Signals: MDC, bidirectional MDIO with output-enable, PHY interrupt.
- Commands return data, timeout and protocol status.
- Software owns link negotiation policy; hardware exposes link and fault events.

## RX parsing and descriptor creation

- Parse a bounded header window at wire rate.
- Initial protocol set:
  - Ethernet and optional stacked VLAN.
  - ARP.
  - IPv4 and IPv6, including bounded extension-header traversal.
  - TCP and UDP.
  - RoCEv2 and selected Ultra Ethernet markers.
- Compute offsets, lengths, tuple/hash, checksum status and parser error.
- Emit `RAW` when parsing is disabled, unsupported or exceeds the configured bound.
- Emit `DISSECTED` when the normalized result is complete.
- Copy or normalize 128 bytes into the descriptor packet view.
- Commit the RX descriptor only after the packet buffer metadata is valid.

## CDC and width conversion

```text
net_clk 312.5 MHz                    proc_clk 400 MHz
160/320b stream -> pack -> async FIFO -> unpack -> 256b stream
256b stream     <- pack <- async FIFO <- unpack <- 160/320b stream
```

- Instantiate one RX and one TX asynchronous FIFO per balanced stream.
- RX converts 160-bit or 320-bit beats to 256-bit beats.
- TX converts 256-bit beats to 160-bit or 320-bit beats.
- Carry data, byte-valid mask, SOP, EOP, error and packet handle through the FIFO.
- Pointer synchronization uses Gray code; reset uses a two-domain empty handshake.
- A partial packing register is part of the FIFO occupancy calculation.
- No packet bytes are exposed after reset until both domains report ready.
- For 800G, each 256-bit/400 MHz lane has only 2.4% raw margin:
  - Keep the steady-state path bubble-free.
  - Size FIFOs for clock tolerance, arbitration latency and maximum packet bursts.
  - Provide a build option for 512-bit processing beats or a faster processing clock if timing analysis removes the margin.

## Packet RAM

### RX-RAM

- Larger packet pool; size is a top-level parameter.
- Eight wire-side write paths, one for each balanced stream.
- `N` logical processing-side read/write ports.
- Dedicated system-side read path for direct card-to-host DMA.
- Store complete frames in fixed-size cells or chained buffers.
- Recommended first implementation: 2 KiB cells plus chaining for jumbo frames.

### TX-RAM

- Smaller packet pool; size is a separate parameter.
- Eight wire-side read paths, one for each TX stream.
- `N` logical processing-side read/write ports.
- Dedicated system-side write path for direct host-to-card DMA.
- Supports header patch writes without copying the full packet.

### Physical organization

- Bank memory by 256-bit word, not by complete packet.
- Use at least eight independently schedulable bank groups.
- Give each wire stream a home bank group for deterministic network service.
- Stripe words across sub-banks inside a group for host and processing concurrency.
- Use true dual-port memory where possible: wire traffic uses the deadline port and host/processing traffic uses the fabric port.
- Increase sub-bank count until worst-case conflict tests meet throughput.
- Present logical ports through queued bank arbiters; do not require a physically multiported RAM macro.
- Reserve bank service for wire RX/TX first, system line-rate DMA second and processing DMA third.
- Maintain per-pool free lists, generation counters and reference counts.
- Detect stale handles, double-free, overflow and underflow in hardware.

## TX field insertion

- Read the descriptor and packet handle before starting a frame.
- Patch fields selected by descriptor flags:
  - Ethernet/VLAN addresses and tags.
  - IPv4/IPv6 addresses and lengths.
  - TCP/UDP ports, lengths and checksums.
  - Sequence, offload and tunnel fields defined by later engines.
- Incremental checksum update is preferred for small patches.
- Full checksum streaming remains available for generated or transformed payloads.
- Reject a descriptor with offsets outside packet bounds.

## Accounting and statistics

- Per port, stream, queue, traffic class and error reason.
- Count packets, bytes, drops, FCS errors, parser fallbacks and RAM starvation.
- Record queue high-water marks, pause duration and DMA stalls.
- Use saturating or wide wrapping counters with explicit semantics.
- Snapshot counters atomically for the host; clear only by an explicit command.

## Backpressure and negotiation

- Internal: FIFO credits and packet-pool watermarks.
- Ethernet: global pause and optional per-priority PFC.
- Host: stop fetching empty RX buffers; expose queue pressure and interrupt the driver.
- Processing: throttle RX descriptor production per queue; spill eligible traffic directly to host or apply drop policy.
- Congestion protocols such as ECN/CNP are packet-processing policy, not a substitute for local buffer safety.
- Every drop point supplies a reason counter and, when possible, a completion.
