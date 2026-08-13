# Sustained 400G SmartNIC video demonstration

The demo runs the complete native C++ sustained 400G capture system. A compact
40-packet image is replayed 64 times at minimum IPG: 2,560 full-size packets and
24,448 uninterrupted Network clocks. This is longer than the modeled complete
receive-buffer absorption interval, so the run must recycle RxRAM while traffic
is still arriving. One video frame is recorded per eight Network clocks at
140 fps. Eight CPU clusters and all clock domains retain their configured
ratios; the observer never changes RTL state.

## Build and run

```text
conda activate ./cpphdl/.conda
cmake -S . -B build
cmake --build build --target smartnic_400g_long_video -j
```

To give the AVI a solid compositing/chroma-key background, invoke the test
directly with an optional six-digit color (shown here with magenta):

```text
build/demo/smartnic_400g_long_demo build/demo/capture.elf \
  demo/output/smartnic_400g_long.avi '#FF00FF'
```

Omitting the background argument uses `(127,127,127)` outside the blocks; all
block interiors use `(195,195,195)`.

Outputs:

- `demo/output/smartnic_400g_long.avi`: 140-fps indexed RLE8 video.
- `demo/output/smartnic_400g_long.csv`: one row per sampled video frame.
- `demo/output/smartnic_400g_long_final.{ppm,bmp,png}`: final previews.
- `demo/output/smartnic_400g_long_{loaded,mid,queue}.png`: event snapshots.

AVI/RLE8 does not define portable alpha-channel semantics, so the long-run AVI
is opaque. APNG output is disabled for this workload because per-frame PNG
compression dominates simulation time. The AVI requires no `ffmpeg`. For an
H.264 copy on a machine with `ffmpeg`:

```text
ffmpeg -i demo/output/smartnic_400g_long.avi -c:v libx264 -crf 18 -pix_fmt yuv420p demo/output/smartnic_400g_long.mp4
```

## Picture layout

```text
+------+--------+----------+-----------+-----------+----------+
| 400G | RX FIFO|          | CPU0      | CPU4      | RX QUEUE |
|      |        |          | L2 I$/D$  | L2 I$/D$  |          |
|channel+-------+  RX RAM  +-----------+-----------+          |
|      | TX FIFO| 8 banks  | CPU1..3   | CPU5..7   +----------+
|      |        |          | L2 I$/D$  | L2 I$/D$  | TX QUEUE |
+------+--------+----------+-----------+-----------+----------+
```

- One colored pixel represents one little-endian two-byte word.
- For word `0xDCBA`, A/B/C select red/green/blue and `D+1` is their gain.
- Packet boundaries, eight RxRAM banks and eight System queues are separated
  by grid lines.
- L2 rectangles show the coherent packet window at `0x00010000`.
- Eight beveled CPU backgrounds are arranged in two columns of four. Each
  smaller I$ rectangle is above its cluster's larger D$ rectangle and
  contains bytes from the actual loaded ELF.
- Demo firmware uses the sustained-test fast path: every descriptor is retired,
  one local packet in ten goes directly to System, and the others are discarded
  after the RxRAM read/release path.
- The capture workload is RX-only, so TX FIFO and TX Queue normally remain empty.

The generator fills complete packets, including the Ethernet-header positions,
with vivid repeating words such as `0x000F`, `0x00F0`, `0x0F00`, `0x00FF`,
`0x0F0F` and `0x0FF0`. The test checks host packet bytes, zero Network-input
backpressure, the absorption-duration proof, continued second-half retirement,
and all existing RTL protocol-error signals.
