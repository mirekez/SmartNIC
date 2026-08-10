# RxRAM

## Purpose

`RxRAM` captures the eight independent framed streams produced by
`InputBalancer` and exposes fewer than eight independently arbitrated packet
read ports. It stores packet bytes without gaps and returns a packet handle and
exact byte length when EOP is accepted.

## Requirements

- Accept eight independent 160-bit (400G) or 320-bit (800G) balanced streams
  every clock, subject only to each stream's own ready signal.
- Remove IPG/invalid-byte holes and align every accepted SOP to an interleave
  block boundary in storage.
- Permit every stream to accept EOP and a following SOP in the same clock,
  including the case where the preceding partial word must also be committed.
- Preserve every packet byte and report an exact length plus a stable handle.
- Provide `N` independent logical read ports for any configured `1 <= N < 8`,
  with fair arbitration for physical-bank collisions and backpressure on both
  request and response paths.
- Give receive writes priority over reads so read contention cannot reduce
  accepted wire throughput.
- Detect malformed framing and storage exhaustion with sticky status outputs.

## Storage organization

- There are eight home-bank groups, one for each receive stream.
- Every group contains two `cpphdl/tribe_cpu/common/RAM.h` sub-banks.
- A logical word is one input-stream beat: 20 bytes for 400G builds and 40
  bytes for 800G builds.
- Consecutive logical words alternate between the two sub-banks.
- A packet handle is aligned to a two-word interleave block. Its low three bits
  identify the home stream; the remaining bits identify the first logical row.
- The address of packet word `i` is `((handle >> 3) + i)`. Its physical bank is
  `2 * (handle & 7) + (logical_row & 1)` and its physical row is
  `logical_row >> 1`.

Two sub-banks are required because an incoming beat can finish one complete
logical word and then end the packet with a second partial word. Those writes
are consecutive and therefore target different sub-banks. This permits all
eight streams to perform that operation, including EOP followed by SOP, in the
same clock.

## Write interface

`valid_in`, `data_in`, `keep_in`, `sop_in`, and `eop_in` use the same packed
eight-stream byte ordering as `InputBalancer`. `ready_out` is independent per
stream. SOP is realigned to byte zero of an aligned storage block; input IPG
holes are discarded. A stream must retain its current beat while its ready bit
is low.

Each completed packet produces:

- `packet_valid_out[stream]`
- `packet_handle_out[stream]`
- `packet_length_out[stream]`

The completion remains stable until `packet_ready_in[stream]` is asserted.

## Read interface

The module has template parameter `READ_PORTS`, constrained to `1..7`. A read
request supplies a packet handle and zero-based logical word index. Requests to
different physical sub-banks proceed together. Requests that collide with one
another are round-robin arbitrated; wire writes have priority. `read_ready_out`
indicates acceptance. Data returns in order on the same logical port through
the `read_valid_out/read_ready_in` response handshake.

The caller uses the completion length to retain only the valid bytes of the
last word: `min(LANE_BYTES, length - word_index * LANE_BYTES)`.

## Bounds and errors

- Maximum encoded packet length is 16383 bytes.
- `BANK_DEPTH` must be a power of two.
- This module is a bounded capture epoch, not the final packet-pool allocator.
  Rows are allocated monotonically after reset and are not reused. When fewer
  than three logical rows remain, the affected stream deasserts ready and sets
  `storage_full_out`. A later pool/free-list layer can provide generation-safe
  reclamation without changing packet addressing.
- Invalid SOP/EOP/keep sequences set sticky `protocol_error_out`.
- Reset clears allocation, completion, arbitration, and response state.

## Typical use

Instantiate `RxRAM<160, N, DEPTH>` for 400G or `RxRAM<320, N, DEPTH>` for
800G. Connect the eight balancer outputs directly to the write interface,
consume completion records into RX descriptors, then read
`ceil(packet_length / LANE_BYTES)` words through any of the `N` read ports.
