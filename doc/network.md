# Network level

## Scope

- Own all wire-rate RX/TX operations.
- PCS, FEC and SerDes are outside this level.
- Run the external datapath at 312.5 MHz.
- Keep RX-RAM storage and native `160/320`-bit ports in `net_clk`.
- Rate-match each 256-bit processing lane to its network lane:
  - 400G: 195.3125 MHz (`312.5 * 160 / 256`).
  - 800G: 390.625 MHz (`312.5 * 320 / 256`).
- Never depend on CPUs responding before an Ethernet deadline.

### PCS adapter and integration verification

- The production Network boundary remains post-PCS/MAC-client data; PCS, FEC,
  PMA and SerDes are not synthesized as part of the SmartNIC.
- `smartnic_test` nevertheless instantiates the selected `eth_pcs` front end:
  - `PCS400G<1280,8>` when `ENABLE_800G == 0`.
  - `PCS800G<2560,8>` when `ENABLE_800G == 1`.
- The test traverses XGMII encode, scramble, virtual-lane distribution,
  descramble and decode in both RX and TX directions before checking frames,
  descriptors and RxRAM contents.
- The current `eth_pcs` 400G/800G aliases end at the Clause 119/172 64B/66B
  front-end boundary.  A standards-complete wire PCS still requires the
  256B/257B transcoder, RS-FEC, alignment-marker insertion/removal, symbol
  interleaving, PMA gearbox and deskew stages documented by that project.
- `/I/` is an explicit XGMII control character.  Deasserting PCS `valid` is
  permitted only between frames for testbench/gearbox rate adaptation; a
  continuous-rate wire adapter must emit idles instead of creating missing
  wire time.
- RX cannot rely on immediate PCS backpressure.  The test therefore requires
  zero Network RX stalls for the generated full-rate traffic.

### IPG accounting

- A transmitting MAC nominally supplies a 12-octet IPG.
- Clause 46/81 deficit-idle accounting aligns `/S/` and may add or remove at
  most three idles while keeping the cumulative deficit bounded.  Starting
  from a 12-octet MAC gap, its transmit-side minimum is therefore 9 octets,
  not 8.
- The integration test intentionally injects RX gaps down to 8 idle octets as
  the requested interoperability/stress case, while keeping the complete
  randomized burst average at least 12 octets.  Passing it is robustness
  evidence; it does not redefine the conforming transmit rule.
- The alignment rule is at the MAC reconciliation/XGMII boundary.  It is not
  an 8-byte PCS quantum and is not caused by alignment-marker insertion;
  downstream transcoding, FEC and marker scheduling are separate.
- SmartNIC TX currently emits at least 12 octets on every boundary and thus
  does not need a deficit counter.

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
net_clk 312.5 MHz               l2_clk 195.3125/390.625 MHz
160/320b stream -> pack -> async FIFO -> unpack -> 256b stream
256b stream     <- pack <- async FIFO <- unpack <- 160/320b stream
```

- Instantiate one RX and one TX asynchronous FIFO per balanced stream.
- RX converts 160-bit or 320-bit beats to 256-bit beats.
- TX converts 256-bit beats to 160-bit or 320-bit beats.
- Pack packet data into 64-byte CDC entries; unpack them to the destination width.
- Carry data, byte-valid mask, SOP and EOP through the stream FIFOs.
- Cross RX descriptors atomically, then expose them as five 256-bit words.
- Cross RxRAM `{handle, length}` commands toward `net_clk`; return framed
  256-bit packet data through a separate CDC stream per read port.
- Pointer synchronization uses Gray code; reset uses a two-domain empty handshake.
- A partial packing register is part of the FIFO occupancy calculation.
- No packet bytes are exposed after reset until both domains report ready.
- The nominal clocks are exact-rate, so CDC buffers absorb phase, arbitration
  and short stalls but do not provide sustained excess bandwidth.
- Keep steady-state paths bubble-free and size FIFOs for bounded stalls.

## Packet RAM

### RX-RAM

- Larger packet pool; size is a top-level parameter.
- Eight wire-side write paths, one for each balanced stream.
- Four current logical processing-side packet-read engines; make the count a
  top-level parameter when the processing DMA is integrated.
- Dedicated system-side read path for direct card-to-host DMA.
- Store complete frames in fixed-size cells or chained buffers.
- Recommended first implementation: 2 KiB cells plus chaining for jumbo frames.

### Physical organization

- Bank memory by 256-bit word, not by complete packet.
- Use at least eight independently schedulable bank groups.
- Give each RX wire stream a home bank group for deterministic network service.
- Stripe words across sub-banks inside a group for host and processing concurrency.
- Current RTL keeps RxRAM in `net_clk` and crosses queued commands/responses.
- Add a true dual-clock/dual-port RAM only when the direct host/system path is
  implemented or measured arbitration cannot meet throughput; do not infer an
  unsafe multi-clock RAM from ordinary registers.
- Increase sub-bank count until worst-case conflict tests meet throughput.
- Present logical ports through queued bank arbiters; do not require a physically multiported RAM macro.
- Reserve bank service for wire RX first, system line-rate DMA second and
  processing DMA third.
- Maintain the RX pool free list, generation counters and reference counts.
- Detect stale handles, double-free, overflow and underflow in hardware.

## TX FIFOs and output merging

- Provide eight independent packet-committed TxFifos. A CPU or host DMA engine
  writes one 160-bit or 320-bit word per selected FIFO per clock with byte
  keep, SOP and EOP.
- Do not expose a partially written packet to the wire side. EOP atomically
  commits all pending words for that packet, allowing arbitrary pauses during
  DMA writes without wire underflow.
- Interleave each FIFO over eight memory banks and expose an eight-word
  show-ahead window so the merger can construct one aggregate `8 x 160/320`
  output word per clock.
- Select committed packets round robin at frame boundaries. Never interleave
  bytes belonging to different frames.
- Carry a partial FIFO word between output clocks and shift subsequent packets
  to any byte offset. Insert exactly the 12-byte minimum IPG when another
  committed packet is ready; a bounded show-ahead-window refill may extend,
  but never shorten, that gap.
- Apply backpressure independently at every TxFifo DMA input. The aggregate
  output holds data, keep, SOP and EOP stable while its ready input is low.
- Header changes, padding and checksum work must be completed before TxFifo
  EOP commit, or applied by a later streaming stage without requiring a
  transmit packet RAM.
- Detect zero or non-prefix keep masks, malformed SOP/EOP sequencing, FIFO
  overflow/underflow and output framing errors with sticky status.

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
