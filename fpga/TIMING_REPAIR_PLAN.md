# Timing repair report

## Accepted routed XC7K325T result — 2026-08-22

Vivado 2026.1 completed synthesis, placement, routing, post-route physical
optimization, DRC, and bitstream generation for `xc7k325tffg676-3`.  The CPU
boot ELF was converted to `capture.mem` before synthesis and is initialized in
the boot BRAM in the generated bitstream.

| Metric | Final value |
|---|---:|
| Setup WNS / TNS | -0.367 ns / -178.016 ns |
| Hold WHS / THS | +0.028 ns / 0 ns |
| Failing setup endpoints | 1,715 of 260,621 |
| Failed / unrouted / partially routed nets | 0 / 0 / 0 |
| `eth_refclk_p` period | 6.400 ns, 156.25 MHz |
| Worst effective setup delay | 6.767 ns, 105.7% of period |
| Requested acceptance threshold | WNS >= -0.500 ns, delay <= 6.900 ns |
| Margin to requested threshold | 0.133 ns |

This result meets the requested WNS threshold.  It does not claim zero-slack
156.25 MHz closure: Vivado correctly continues to label the remaining negative
setup slack as a timing violation.  All GTX RX/TX intra-clock groups and all
inter-clock paths have positive setup slack.  The only negative group is the
shared `eth_refclk_p` domain used by Network, Processing, and CPU.

### Repair plan completed

1. **Classify the routed failures.** The two largest architectural problems
   were the L1-to-L2 live arbitration/control cone and a 4,096-flip-flop TX EOP
   metadata array with asynchronous read muxes.  PacketParser, CPU writeback,
   DescriptorFetcher, PacketDMA, RxRAM, and OutputMerger were retained as the
   next timing-driven candidate set.
2. **Repair Network-to-System storage without reducing bandwidth.**
   `TxEopMemory` now uses two replicated distributed-RAM read copies, retaining
   both asynchronous scheduler read ports and the existing dequeue rate.  The
   4,096 metadata flip-flops disappeared; focused OutputMerger synthesis reached
   WNS +0.512 ns.
3. **Create an honest L1/L2 boundary.** L2 captures an accepted request in a
   request-pipe register before arbitration/FSM work.  L2 data and tag storage
   use small CppHDL leaf modules backed by inferred dual-port BRAM primitives.
   The controller itself is generated from CppHDL, not replaced by a large SV
   module.  Focused L2 timing reached WNS -0.205 ns.
4. **Keep protocol throughput.** PacketParser keeps its protocol-family
   pipeline; RxRAM row arithmetic, DescriptorFetcher address/read staging,
   PacketDMA address capture, and OutputMerger's two-entry batch queue remain
   pipelined.  The final sustained dual-10G AXI test passes.  L2 now issues its
   synchronous RAM read while consuming the request-pipe entry, so the timing
   boundary does not add a normal-request controller cycle; `ST_READ` is used
   only to retry when coherent DMA owns the RAM port.
5. **Use physical optimization only after RTL repair.** The first complete
   route reached WNS -0.502 ns.  Reproducible post-route `Explore` optimization
   then shortened equivalent CPU writeback/cache-request and parser field paths,
   producing final WNS -0.367 ns.  This step is enabled in
   `create_project.tcl` for future clean builds.

Top synthesis completed in 26m25s with a 9.5 GiB main-process peak, zero errors,
and zero critical warnings.  This removes the prior multi-hour/runaway synthesis
behavior.  The final regression passes 16/16 tests, including the 108.79-second
`system_capture_2x10g_sustained` AXI test.

### Clock, CDC, and implementation checks

- Network, Processing, all four L1 caches, and L2 use the same honest 156.25 MHz
  clock.  No functional L1/L2 multicycle or false-path exception hides setup
  timing; the registered request protocol provides the required boundary.
- Processing-to-System traffic uses the specialized AXI4 path and asynchronous
  FIFOs/handshakes where clock domains differ.  All reported bus-skew checks
  pass; the smallest slack is +5.934 ns.
- Routed DRC contains no Error or Critical Warning rules.  The remaining three
  LUT warnings and one no-routable-load warning are within the generated debug
  hub; three BRAM advisories are within the PCIe IP.
- Only the main system-clock ILA is enabled, probing PLL/GTX/10G/system status.

Generated evidence:

- `build/open_switch.runs/impl_1/klusterlab_top_postroute_physopt.dcp`
- `build/open_switch.runs/impl_1/klusterlab_top_timing_summary_postroute_physopt.rpt`
- `build/open_switch.runs/impl_1/klusterlab_top_drc_postroute_physopt.rpt`
- `build/open_switch.runs/impl_1/klusterlab_top_bus_skew_postroute_physopted.rpt`
- `open_switch.bit`, `open_switch.bin`, and `open_switch.ltx`

## Historical failing baseline

The original report contained the failures below.  It is retained to document
why clock/CDC correction and RTL refactoring were necessary.

| Problem | Original worst slack | Original failing endpoints | Resolution |
|---|---:|---:|---|
| CPU to CPU | -96.846 ns | 47,587 | Shared honest 156.25 MHz clock; further pipeline work for 6.4 ns |
| Ethernet to Ethernet | -32.757 ns | 16,378 | Parser/RxRAM pipeline refactor; now 8.089 ns worst Network path |
| Ethernet to CPU | -92.029 ns | 55,268 | Removed invalid 312.5/156.25 direct boundary |
| CPU to Ethernet | -29.241 ns | 9,122 | Removed invalid 312.5/156.25 direct boundary |
| Startup to GTX TX | -3.504 ns | 8 | Free-running source counter; synchronized toggle only |
| GTX TX to Ethernet | -2.961 ns | 14 | Two-flop toggle/status synchronization |
| Startup to Ethernet | -1.713 ns | 11 | Diagnostic first-stage exception; reset issue documented above |

## 0. Clock and constraint audit

Before changing RTL:

1. Confirmed intended clocks:
   - Processing/CPU/L1/L2/Network: 156.25 MHz, 6.4 ns.
   - Startup: 50 MHz, 20 ns.
   - GTX TX/RX user clocks: approximately 322.27 MHz, 3.103 ns.
2. `report_clock_interaction`, detailed `report_cdc`, module timing, exception
   coverage, route status, and bus-skew reports were generated from the final
   routed DCP.
3. Classify every crossing as one of:
   - Synchronous functional path.
   - Valid multicycle transfer.
   - Handshake/asynchronous FIFO CDC.
   - Reset synchronization.
   - Debug-only sampling.

Only proven asynchronous first synchronizer stages were false-pathed.  No
functional L1/L2 or Processing/Network multicycle constraint was added.

## 1. CPU to CPU: -96.846 ns

Worst path: core-3 D-cache tag RAM to CPU pipeline `rs2_val`. Similar logic is
replicated across all four cores.

Affected modules:

- `L1CacheState___tag_ram`, instruction and data caches.
- CPU pipeline state, register storage and forwarding.
- `CSR`, `Execute`, `ExecuteMem`, and `WritebackMem`.
- Shared `L2Cache`.
- Instruction/data memory CDC response logic.
- `DescriptorFetcher` and large processing queues.

Investigation:

1. High fanout search:
   - Report fanout for cache stall, cache wait, register write, pipeline valid,
     invalidate, and refill control nets.
   - Identify nets replicated across many state-structure fields.
   - Check whether large decoded state buses drive every pipeline stage.
2. Reset involvement check:
   - Separate reset/enable paths from functional data paths.
   - Check whether resettable wide structures prevent BRAM/SRL inference or
     retiming.
   - Remove reset from data registers where only a valid bit needs reset.
3. Longest-chain investigation:
   - Measure logic levels and logic-versus-routing delay for BRAM to tag
     comparison to refill/load alignment to forwarding to pipeline state.
   - Inspect DSP warnings in ALU/CSR logic.
   - Separate cache-hit, refill, split-load, and exception paths.
   - Run isolated synthesis for one core and one cache before rebuilding all
     four cores.
4. Fix/redesign decision:
   - Small fanout replication will not repair a roughly 100 ns path.
   - Expected fixes require additional registered boundaries around cache
     responses, load alignment, CSR decode, and forwarding.
   - If ISA-visible behavior prevents those registers, report the module as
     unfixable locally and redesign the CPU pipeline/handshake.
   - Preliminary result: architectural redesign is required, not placement
     tuning.

## 2. Ethernet to Ethernet: -32.757 ns

Worst path: channel-0 parser `ipv4_progress.state[7]` to parser pipeline stage-4
progress state.

Affected modules:

- Both independent `PacketParser` instances.
- IPv4 progress logic.
- IPv6 extension index, size, and progress logic.
- Parser pipeline stage 4.
- `RxRAM`: `used_rows`, `storage_full`, deferred release, and protocol-error
  logic.
- Both `InputBalancer` FIFO instances.
- Network protocol-error aggregation.

Investigation:

1. High fanout search:
   - Check parser progress state, `done`, `limit`, header-state, and
     extension-index fanout.
   - Check `RxRAM.used_rows`, `storage_full`, release, and protocol-error
     fanout.
   - Locate wide predicates duplicated for every byte/field.
2. Reset involvement check:
   - Determine whether parser field/progress registers all reset unnecessarily.
   - Reset only valid/state bits when data is ignored while invalid.
   - Separate asynchronous network reset from normal parser state transitions.
3. Longest-chain investigation:
   - Extract paths by parser stage and protocol family.
   - Count LUT levels for IPv4, VLAN/MPLS, IPv6, and each extension stage.
   - Check whether stage 4 recomputes previous-stage markup instead of
     consuming registered results.
   - In `RxRAM`, inspect wide occupancy arithmetic, release scanning, and error
     aggregation in one cycle.
   - Synthesize `PacketParser`, `RxRAM`, and `InputBalancer` separately at
     6.4 ns and 9.6 ns.
4. Fix/redesign decision:
   - Parser paths should be fixed by repartitioning protocol-family work across
     registered stages without reintroducing stream sharing.
   - `RxRAM` likely needs registered occupancy/error calculations.
   - If a stage intrinsically evaluates the complete recursive header tree in
     one cycle, classify it as unfixable and redesign the C++ CppHDL stage
     boundary.
   - Preliminary result: RTL redesign is required; physical optimization alone
     recovered less than one nanosecond.

### Ethernet repair performed

The Ethernet-to-Ethernet path is the first repair target.  The accepted relaxed
milestone is a maximum functional data-path delay of 9.6 ns (150% of the
6.4 ns Ethernet period); this is deliberately different from declaring true
156.25 MHz timing closure.

The original detailed routed recheck, restricted to sequential endpoints
inside `nic/network`, showed concrete architectural problems which were hidden
by the older global summary:

- 15.407 ns, 24 logic levels: `InputBalancer` BRAM output directly through the
  parser/RxRAM selection logic to an `RxRAM` write-data register.
- 14.983 ns, 27 logic levels: packet ingress SOP/realignment logic directly to
  parser pending state.

Repairs made in the C++ CppHDL sources:

1. `Network` now has one independent elastic receive register per Ethernet
   channel.  Parser and `RxRAM` consume the registered channel word atomically;
   simultaneous consume/refill preserves one word per channel per cycle.
2. `PacketParser` now registers a realignment event containing up to two
   aligned output words.  The ingress byte scan no longer directly drives the
   pending/parser-pipeline state in the same cycle.
3. Runtime markup predicates were removed from the generated datapath while
   retaining the requested `markup_pos`/`markup_state` function-call structure.
   The markup value is a compile-time path description, so rechecking at
   runtime only duplicated wide predicates.
4. RAW capture length is derived from the completed emitted word and byte
   position at EOP.  The former per-byte running RAW counter and its wide
   update mux are no longer on the parser critical path.
5. `PacketParser` ingress is now a scanner followed by an arithmetic realigner
   and the registered protocol-family pipeline.  The scanner emits a compact
   event; it no longer drives protocol state through a byte-wise mux cascade.
6. `RxRAM` now registers a compact, per-channel scan event with at most two
   frame segments.  The following cycle packs those segments with two
   arithmetic shift/OR operations.  This removes the serial SOP/EOP/error and
   byte-packing chain from the RAM write-data path while preserving one input
   word per channel per clock.

Module results before full implementation:

| Module/check | Result |
|---|---:|
| `InputBalancer` isolated data delay | 2.696 ns |
| `RxRAM` isolated routed data delay | 7.203 ns (WNS -1.159 ns at 6.4 ns) |
| `OutputMerger` isolated data delay | 6.627 ns |
| `PacketParser` isolated routed data delay | 6.365 ns (WNS +0.006 ns at 6.4 ns) |
| Ethernet/SmartNIC regressions | 9/9 passed, 216.44 s |

The first full-device implementation after the parser repair exposed the next
true bottleneck: a 15.626 ns, 28-level path from
`receive_sop_reg_reg[1][0]` to `rx_ram/write_data1_reg_reg[1][6]`.  This was the
`RxRAM` serial ingress scanner and packer, not the protocol parser.  The
`RxRAM` repair above reduces every isolated routed `RxRAM` path to 7.203 ns or
less.  Its remaining worst path is deferred-release handle bookkeeping, so the
ingress path is no longer the module bottleneck.

The Ethernet report script now selects both launch and capture sequential cells
under `nic/network/*`.  This is important: selecting paths by the top-level
`eth_refclk_p` clock also included derived CPU clocks and incorrectly reported a
CPU failure as an Ethernet failure.  A clean XC7K325T implementation and this
exact routed Network-only report are required for final acceptance.

## 3. Ethernet to CPU: -92.029 ns

Worst path: `d_mem_cdc/read_data_slow_reg[159]` into core-3 pipeline state.

Affected modules:

- `d_mem_cdc` and likely equivalent `i_mem_cdc`.
- CPU cache response and core pipeline consumers.
- Network/processing memory response interface.
- Descriptor and packet-data transfer interfaces.

Investigation:

1. High fanout search:
   - Check synchronized `valid`, `wait`, response-data, and transaction-owner
     signals.
   - Determine whether one CDC control bit enables thousands of CPU registers.
2. Reset involvement check:
   - Confirm independent reset synchronization on both sides.
   - Verify asynchronous assertion and synchronous deassertion.
   - Ensure reset does not act as the data-transfer protocol.
3. Longest-chain investigation:
   - Determine whether the 160/256-bit response is stable under a handshake or
     crosses directly.
   - Trace from the slow-domain holding register through CPU cache/decode logic.
   - Verify whether the intended 2:1 synchronous relationship permits a
     justified multicycle constraint.
   - Run CDC structural checks and assertions for data stability until
     acknowledgement.
4. Fix/redesign decision:
   - If a stable-data handshake already guarantees two or more CPU cycles, add
     the matching multicycle constraint with the corresponding hold adjustment.
   - If data can change while being sampled, replace it with an asynchronous
     FIFO, toggle handshake, or registered request/response bridge.
   - Never false-path the data bus without proving its stability.
   - Preliminary result: CDC protocol or constraint architecture must be
     repaired before datapath optimization.

## 4. CPU to Ethernet: -29.241 ns

Worst path: `PacketDMA.operation_reg` to the asynchronous set pin of
`RxRAM.protocol_error_reg`.

Affected modules:

- `PacketDMA`.
- `RxRAM`.
- Protocol-error aggregation.
- Descriptor-valid/ready and packet-control crossings.

Investigation:

1. High fanout search:
   - Check `operation`, descriptor-valid, error, release, and DMA completion
     controls.
   - Find CPU-domain signals feeding multiple network state machines.
2. Reset involvement check:
   - The worst endpoint is an asynchronous set pin, so reset/set involvement is
     central.
   - Remove functional error signalling through asynchronous set/reset pins.
   - Synchronize error events as toggles or handshakes.
3. Longest-chain investigation:
   - Trace every CPU control entering `RxRAM` or `Network`.
   - Separate functional DMA transactions from diagnostic/error flags.
   - Check whether descriptor and release buses cross without a FIFO.
4. Fix/redesign decision:
   - Replace asynchronous error setting with a synchronized event or sticky
     flag maintained in the destination domain.
   - Use an asynchronous FIFO for descriptors/data when payload accompanies the
     event.
   - Preliminary result: fixable through CDC interface redesign; timing
     optimization is not the correct solution.

## 5. Startup to GTX TX: -3.504 ns

Worst path: `por_shift_reg[7]` to `txusr_heartbeat_reg[0]/R`.

Affected modules:

- POR/startup reset generator.
- TX-user-clock heartbeat.
- GTX reset/debug instrumentation.

Investigation:

1. High fanout search: check `por_shift`, `startup_reset`, and GTX reset fanout.
2. Reset involvement check: this path is entirely reset-related.
3. Longest-chain investigation: verify asynchronous assertion and synchronous
   deassertion in TXUSRCLK.
4. Fix/redesign decision: add a TXUSRCLK-domain reset synchronizer or make the
   heartbeat free-running with only its valid flag reset. Mark only the
   synchronizer's asynchronous input as a false path.

This is a local, fixable problem.

## 6. GTX TX to Ethernet: -2.961 ns

Worst path: `txusr_heartbeat` into the system ILA.

Affected modules:

- TX-user-clock heartbeat counter.
- System ILA probe packing.

Investigation:

1. High fanout search: inspect heartbeat counter bits and ILA probe replication.
2. Reset involvement check: ensure heartbeat reset is local to TXUSRCLK.
3. Longest-chain investigation: confirm this is debug-only and does not feed
   functional logic.
4. Fix/redesign decision: replace the raw multibit counter crossing with a
   single toggle bit, synchronize it into `net_clk`, and optionally count
   synchronized toggles in the ILA domain.

This is a straightforward debug CDC fix.

## 7. Startup to Ethernet: -1.713 ns

Worst paths involve `por_shift_reg`, the first network reset synchronizer stage,
and system ILA probes.

Affected modules:

- POR generator.
- `net_reset_sync`.
- Main system ILA status packing.

Investigation:

1. High fanout search: report startup reset/lock fanout.
2. Reset involvement check: identify all asynchronous first-stage synchronizer
   pins.
3. Longest-chain investigation: separate functional reset synchronizers from
   raw status probes.
4. Fix/redesign decision:
   - Mark synchronizer registers `ASYNC_REG`.
   - False-path only to the first synchronizer stage.
   - Synchronize startup/PLL status signals before the ILA samples them.
   - Do not false-path functional network state.

This is locally fixable.

## Recommended execution order

1. Audit clocks and constraints.
2. Fix startup/reset and debug-heartbeat crossings.
3. Repair CPU-to-Ethernet and Ethernet-to-CPU functional CDC.
4. Isolate and repair `PacketParser`, `RxRAM`, and `InputBalancer`.
5. Redesign CPU cache/pipeline paths.
6. Re-run isolated synthesis after every module change.
7. Run full place/route only when isolated modules are below the chosen delay
   limit.

For the relaxed first milestone, every functional path should be below 9.6 ns.
True 156.25 MHz closure still requires 6.4 ns, and a 312.5 MHz CPU requires
3.2 ns. Any module that cannot reach its target after fanout, reset, and chain
investigations must receive an explicit "requires redesign" report containing
its top paths, logic levels, fanout, attempted fixes, and required new
pipeline/handshake boundary.
