# 800G SmartNIC video demonstration

The demo runs the complete native C++ 800G capture system and records one
500x300 video frame after every twentieth evaluated 312.5 MHz Network clock. The
workload contains 640 packets—four times the preceding demo and twenty times
the original traffic—while 20:1 visual decimation and 140-fps playback keep the
video duration at approximately the original 36 seconds. Eight CPU clusters,
their L1/L2 caches, and
System domains continue at their configured ratios. The observer never changes
RTL state.

## Build and run

```text
conda activate ./cpphdl/.conda
cmake -S . -B build
cmake --build build --target smartnic_800g_video -j
```

To give the AVI a solid compositing/chroma-key background, invoke the test
directly with an optional six-digit color (shown here with magenta):

```text
build/demo/smartnic_800g_demo build/demo/capture.elf \
  demo/output/smartnic_800g.avi '#FF00FF'
```

The transparent APNG uses the selected background palette entry as its alpha
key. Omitting the argument uses `(127,127,127)` outside the blocks; all block
interiors use `(195,195,195)`.

Outputs:

- `demo/output/smartnic_800g.avi`: 140-fps indexed RLE8 video.
- `demo/output/smartnic_800g_transparent.png`: synchronized 140-fps APNG with
  a transparent canvas background for overlays and compositing.
- `demo/output/smartnic_800g.csv`: one row per video/Network clock.
- `demo/output/smartnic_800g_final.ppm`: final-frame preview.
- `demo/output/smartnic_800g_final.bmp`: widely viewable final-frame preview.
- `demo/output/smartnic_800g_final.png`: browser-friendly final-frame preview.
- `demo/output/smartnic_800g_loaded.png`: generator fully loaded.
- `demo/output/smartnic_800g_mid.png`: middle of the wire burst.
- `demo/output/smartnic_800g_queue.png`: first observed System RxQueue packet.

AVI/RLE8 does not define portable alpha-channel semantics, so the AVI remains
opaque and the same run writes a transparent APNG alongside it. Neither output
requires `ffmpeg`. For an H.264 copy of the AVI on a machine with `ffmpeg`:

```text
ffmpeg -i demo/output/smartnic_800g.avi -c:v libx264 -crf 18 -pix_fmt yuv420p demo/output/smartnic_800g.mp4
```

## Picture layout

```text
+------+--------+----------+-----------+-----------+----------+
| 800G | RX FIFO|          | CPU0      | CPU4      | RX QUEUE |
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
- Demo firmware reads the first 40 bytes of every packet after Network-to-CPU
  DMA. The two resulting 32-byte refill lines are shown in D$ while its frame
  remains static.
- The capture workload is RX-only, so TX FIFO and TX Queue normally remain empty.

The generator fills complete packets, including the Ethernet-header positions,
with vivid repeating words such as `0x000F`, `0x00F0`, `0x0F00`, `0x00FF`,
`0x0F0F` and `0x0FF0`. The test still checks every host packet byte, zero Network-input
backpressure, and all existing RTL protocol-error signals.
