# PacketParser 3.2 ns Timing-Closure Plan

## Objective

Close timing at a 3.2 ns clock period (312.5 MHz) for both 160-bit and
320-bit per-queue PacketParser instances while preserving:

- One accepted aligned word per cycle when downstream is ready.
- Independent packet streams for all eight queues.
- Per-byte, on-the-fly field capture.
- The `markup_pos, markup_state` parser-call convention.
- One parser function per header occurrence, including VLAN, MPLS, and IPv6
  extension occurrences.
- Packet ordering, RAW handling, malformed-packet behavior, and backpressure.

Increasing pipeline latency is acceptable. Reducing steady-state throughput is
not.

## Implementation result (2026-08-20)

The parser now uses 49 registered stages:

```text
aligned input -> ingress bounds -> Ethernet
      -> (decode -> resolve) x VLAN1..4
      -> (decode -> resolve) x MPLS1..4
      -> IPv4 base -> IPv4 options -> IPv6 base
      -> (byte decode -> extent calculation -> parse/transition) x IPv6-ext1..8
      -> transport decode -> TCP -> UDP/completion
```

This preserves the standard `markup_pos, markup_state` function convention and
the separately elaborated `parse_vlan1()`/`parse_vlan2()`,
`parse_mpls1()`/`parse_mpls2()`, and `parse_ipv6_options1()` through
`parse_ipv6_options8()` functions. Completed extension occurrences retain and
forward their resolved progress until the next SOP, which is required when an
extension crosses an aligned-word boundary. Ingress marker scanning is isolated
from alignment by a registered segment descriptor. RAW data emission has its
own two-slot registered batch, so neither boundary scanning nor RAW collection
is on the alignment critical path.

Measured 320-bit timing progression on `xcu250-figd2104-2L-e`:

| Revision | Stages | Synth delay | WNS at 3.2 ns | Critical block |
|---|---:|---:|---:|---|
| Per-occurrence protocol pipeline | 22 | 4.951 ns | -1.769 ns | IPv6 extension |
| Post-route baseline | 22 | 4.970 ns | -1.759 ns | IPv6 extension |
| Registered extension byte decode | 30 | 4.767 ns | -1.585 ns | IPv6 extension resolution |
| Registered extension extent | 38 | 4.980 ns | -1.897 ns | combined TCP/UDP stage |
| Separate TCP and UDP stages | 39 | 4.884 ns | -1.702 ns | transport decode |
| Registered ingress bounds | 40 | 4.322 ns | -1.140 ns | VLAN/ingress decode |
| VLAN/MPLS decode cuts and 32-word output FIFO | 48 | 4.401 ns | -1.219 ns | RAW ingress |
| Registered ingress segment descriptor | 48 | 3.728 ns | -0.546 ns | RAW alignment |
| Registered RAW emission batch | 49 | 3.290 ns | **-0.194 ns** | RAW emit slot enable |

The 49-stage revision passes native CppHDL parser tests and exact generated-RTL
Verilator parser tests at both 160 and 320 bits, with randomized backpressure
and continuous line-rate cases. Integrated native Network tests also pass the
parsed, RAW, and TX paths at both widths. The native 400G SmartNIC + PCS test
passes RX descriptor/RAM handling, TX aggregation, pause/idle controls, and
inter-packet-gap checks.

The 320-bit result is from timing-driven Vivado 2022.2 OOC synthesis on
`xcu250-figd2104-2L-e` with a 3.2 ns clock. It reports 68,907 LUTs and 61,136
flip-flops. The remaining -0.194 ns WNS is accepted temporarily for this
revision. A subsequent functionally verified cleanup makes RAW emit payload
register writes unconditional and qualifies them with the valid register; it
has not been re-run through Vivado because timing work stopped at the accepted
checkpoint.

## Measured baseline

| Configuration | 160-bit delay | 320-bit delay | Dominant cause |
|---|---:|---:|---|
| Current six-stage parser | 50.511 ns | 52.424 ns | IPv4, IPv6, and all eight IPv6-extension occurrences chained in one stage |
| Earlier per-occurrence pipeline | 7.402 ns | 6.466 ns | A single occurrence still contains 25-30 logic levels |
| Current 320-bit ingress | N/A | 6.821 ns | Boundary scan, alignment, counters, and RAW storage in one cycle |

Historical reports are in:

- `build/vivado_packet_parser_family_160/timing_summary.rpt`
- `build/vivado_packet_parser_family_320/timing_summary.rpt`

The accepted 320-bit report is in:

- `build/vivado_packet_parser_raw_emit_320/timing_summary.rpt`
- `build/vivado_packet_parser_raw_emit_320/utilization.rpt`

The work therefore has two independent timing targets: the header parser and
the ingress realigner/RAW collector. Restoring register cuts fixes the 50 ns
chain, but cannot by itself reach 3.2 ns.

## Phase 1: Make the Vivado measurement timing-driven

Update `rtl/network/tests/synth_packet_parser.tcl` so that the 3.2 ns clock is
applied before synthesis. The current script creates the clock after
`synth_design`, so synthesis is not optimized against the required period.

The timing flow will:

1. Read the generated SystemVerilog and a 3.2 ns XDC constraint.
2. Run timing-driven out-of-context synthesis.
3. Run `opt_design`, `place_design`, `phys_opt_design`, and `route_design`.
4. Generate post-synthesis and post-route timing summaries.
5. Generate utilization, logic-level, high-fanout, congestion, and clock
   reports.
6. Run both 160-bit and 320-bit configurations on
   `xcu250-figd2104-2L-e` with Vivado 2022.2.

Post-route timing is the sign-off result. Post-synthesis timing is only an
iteration aid.

## Phase 2: Restore one registered stage per header occurrence

Replace the six-stage schedule with the following progression:

```text
input
  -> Ethernet
  -> VLAN1 -> VLAN2 -> VLAN3 -> VLAN4
  -> MPLS1 -> MPLS2 -> MPLS3 -> MPLS4
  -> IPv4 -> IPv6
  -> IPv6-ext1 -> IPv6-ext2 -> ... -> IPv6-ext8
  -> TCP/UDP
  -> completion
```

This is approximately 21 parser stages. IPv4 and IPv6 are mutually exclusive;
the inactive branch passes the progress token unchanged. Likewise, header
occurrence stages become pass-through stages when their header is absent.

Each input word remains attached to its `PacketParserPipeWord` as it crosses
the stages. Consequently, several headers contained in the same 160-bit or
320-bit word can be processed on successive cycles without buffering the whole
packet. The pipeline continues accepting one word per cycle.

Implementation requirements:

- Retain `parse_vlan1()` through `parse_vlan4()`.
- Retain `parse_mpls1()` through `parse_mpls4()`.
- Retain `parse_ipv6_options1()` through `parse_ipv6_options8()`.
- Give each occurrence a statically indexed stage implementation. Do not route
  a runtime occurrence index through a common array-indexed function.
- Keep local progress and captured-field registers for each occurrence.
- Pass `error`, `limit`, and `done` forward without permitting later stages to
  restart parsing.
- Update in-flight EOP/FIFO reservation accounting for the larger number of
  pipeline stages.

Expected result: remove the current 50-52 ns IPv6-extension chain and return
to approximately the earlier 6-7 ns range before local stage optimization.

## Phase 3: Reduce each header stage below the clock budget

The earlier per-occurrence pipeline still failed 3.2 ns, so every occurrence
stage must be made shallower.

### 3.1 Preserve markup semantics without a dynamic critical-path lookup

Keep the standard parser API:

```text
markup_pos, markup_state, progress, word, word_bytes, word_cntr
```

Each parser function continues writing its header ID into
`markup_state[markup_pos]` and returning the modified markup. However, avoid a
dynamic `markup_state[markup_pos]` read on the registered progress-update path
when the caller has just marked that same header. Use the current function's
statically known header token to qualify real work, while retaining returned
markup for same-word call-stack semantics.

### 3.2 Predecode byte location once

For each active header occurrence, calculate once per stage:

- Whether the header begins in the current word.
- Its word-relative byte offset.
- Which required fields overlap the current word.
- Whether the minimum or complete header ends in the current word.

Do not repeat absolute-position arithmetic, range comparisons, and dynamic
byte selection independently for every captured byte.

### 3.3 Use balanced field extraction

- Replace serial priority assignments with balanced lane selection.
- Decode the valid lane once and share that decode across captured fields.
- Capture fixed-width fields in parallel.
- Use minimum-width CppHDL integer types for offsets, counters, and selectors.
- Express the power-of-two header IDs as one-hot state tests where possible,
  instead of repeated full-width equality chains.

### 3.4 Make progress resolution single-assignment

Each stage will construct one local next-progress value and assign each state
register once. This removes long `_next` feedback and conditional-priority
chains. Header completion has explicit priority over capture-in-progress,
followed by error/limit propagation.

The target is approximately 2.7-2.8 ns maximum per parser stage, reserving
routing margin inside the 3.2 ns period.

If a stage remains over budget, register only feed-forward extraction results.
Do not blindly register the previous-word state recurrence: consecutive words
from one queue depend on that state. Any internal cut must include explicit
previous-word forwarding or keep the recurrence decision in a single short
control stage.

## Phase 4: Pipeline ingress boundary decoding and realignment

Split the monolithic ingress block into three operations.

### 4.1 Boundary decoder

- Validate `keep`, `sop`, and `eop` consistency.
- Find kept-byte bounds and SOP/EOP positions with balanced encoders.
- Produce zero, one, or two segment descriptors. Two descriptors represent the
  tail of one packet and the head of the next packet in the same queue beat.

### 4.2 Segment extraction

- Shift and mask the selected segment using registered descriptor positions.
- Keep this operation stateless so descriptors can be pipelined every cycle.

### 4.3 Alignment and emission

- Append one extracted segment to the alignment residue.
- Emit an aligned lane word when enough bytes are present.
- Flush a partial word at EOP.
- Place the possible second rollover segment in a small descriptor FIFO.
- Apply input backpressure based on descriptor capacity rather than a long
  combinational pending-data path.

This preserves one-word-per-cycle operation for normal traffic and preserves
the existing legal backpressure behavior for packet rollover beats.

## Phase 5: Remove the wide RAW read-modify-write path

Replace `raw_data_low_reg`/`raw_data_high_reg` accumulation with banked aligned
lane-word storage:

1. Store each emitted 160-bit or 320-bit aligned word in a statically selected
   slot.
2. Maintain only a short word count and final byte count in the active bank.
3. At RAW EOP, enqueue a completed-bank token in packet order.
4. Serialize that bank into the required two 512-bit output words after the
   parser-order token reaches completion.
5. Use enough banks to retain the current RAW buffering and rollover behavior.

This removes a 1024-bit feedback mux from the ingress cycle and bounds storage
selection by the number of lane words in a RAW capture.

## Phase 6: Iterative timing closure

After every architectural change:

1. Build and run the native CppHDL parser tests for both widths.
2. Regenerate SystemVerilog.
3. Compile and run the Verilator parser tests for both widths.
4. Run 320-bit OOC Vivado synthesis first because it is the 800G worst case.
5. Inspect at least the 20 worst paths, grouped by source and destination
   stage, rather than optimizing only the single WNS path.
6. Repeat for 160 bits when 320-bit timing is close to closure.
7. Run placed-and-routed timing for both widths.

Optimization order after the major cuts:

1. Remaining parser occurrence paths.
2. Ingress boundary/realignment paths.
3. RAW storage paths.
4. FIFO reservation and ready paths.
5. High-fanout control nets and placement congestion.

Physical directives, register duplication, and `phys_opt_design` are final
tools, not substitutes for removing combinational chains.

## Functional verification

The regression must cover:

- Untagged Ethernet with IPv4 and IPv6.
- One through four VLAN headers.
- One through four MPLS labels.
- IPv4 minimum headers and maximum supported options.
- IPv6 with zero through eight extension headers.
- TCP minimum headers and supported TCP options.
- UDP.
- Initial and non-initial IPv4/IPv6 fragments.
- Unsupported protocols, malformed headers, and configured limit handling.
- Headers crossing every possible 160-bit and 320-bit word boundary.
- Packet rollover within one queue beat.
- RAW and parsed packets interleaved in order.
- Randomized downstream backpressure.
- Continuous line-rate words with downstream ready.

After the parser tests pass, run `network_basic_tests` and `smartnic_test` for
400G integration coverage.

## Sign-off criteria

The change is complete only when all of the following are true:

- Post-route WNS is at least 0 ns at a 3.2 ns period for both 160-bit and
  320-bit PacketParser instances. Formal sign-off remains future work; for the
  2026-08-20 synthesis checkpoint, the user explicitly accepted the measured
  320-bit WNS of -0.194 ns as the temporary stopping point.
- Post-route TNS is 0 and there are no hold violations.
- Native CppHDL and generated-Verilator parser regressions pass.
- Network and 400G SmartNIC integration regressions pass.
- The parser sustains one accepted aligned word per cycle whenever downstream
  is ready and no documented rollover backpressure is required.
- Synthesis contains no unbounded 512-by-512 muxes or equivalent wide dynamic
  storage-selection structures.
- Utilization remains practical for eight parser instances; any large increase
  from the measured baseline is reviewed before sign-off.
- `/root/SmartNIC` remains unchanged and is used only as a reference.
