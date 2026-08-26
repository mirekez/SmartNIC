# Eight-CPU SmartNIC capture video

The demo compiles and runs the real `test/capture.cpp` functional full-system
test with visualization enabled. The observer only reads public C++HDL state:
it does not alter RTL behavior. All 640 packets must pass the normal host,
protocol, backpressure, L2 and private-DDR assertions before the run succeeds.

## Build and run

```text
conda activate ./cpphdl/.conda
cmake -S . -B build
cmake --build build --target smartnic_capture_video -j
```

Run directly to select another output path or background color:

```text
build/demo/smartnic_capture_demo build/demo/capture_8cpu.elf \
  demo/output/capture.avi '#7F7F7F'
```

Block interiors are `(195,195,195)` and the default outside background is
`(127,127,127)`.

Generated files use the stem `demo/output/smartnic_capture_8cpu_32core`:

- `.avi`: 800x480, 60-fps indexed RLE8 video.
- `.csv`: per-frame clock and traffic counters.
- `_final.{ppm,bmp,png}`: final stills.
- `_loaded.png`, `_mid.png`, `_queue.png`: event snapshots.

## Picture layout

```text
+--------+--------+--------+-------------------------------+----------+
| 400G   | RXFIFO | RX RAM | CPU0 / four horizontal cores  | RX QUEUE |
| channel+--------+ banks  | CPU1 ... CPU7, 2 x 4 packages |          |
|        | TXFIFO |        | each: shared L2 + 4 x I$/D$   | TX QUEUE |
+--------+--------+--------+-------------------------------+----------+
| DDR0 ring | DDR1 ring | ... independent DDR6 / DDR7 packet rings   |
+--------------------------------------------------------------------+
```

- The CPU packages use the beveled grayscale background brought forward from
  the `open_switch2` demo.
- Every package contains its complete shared L2 view and four distinct core
  tiles. Each core has a smaller instruction-cache panel above its data-cache
  panel.
- The bottom row shows the complete 512-slot, 1-MiB packet-ring region of
  every CPU's private DDR. The ring is proportionally folded into its panel;
  occupied words are contiguous and no decorative spaces are inserted.
- FIFO, RxRAM and cache renderers show two-byte words without the previous
  five-pixel packet spacing. If storage exceeds its panel, every source range
  contributes to a proportionally folded destination pixel.
- Bright packet colors are derived from repeating little-endian 16-bit words.
  For `0xDCBA`, A/B/C select red/green/blue and `D+1` is their gain.
- The RX queue keeps its two most recent completed transfers visible so short
  live residency does not disappear between decimated video frames.

The capture workload is RX-only, so Network TX FIFO and System TX Queue remain
empty. Every packet is loaded through PacketDMA into the corresponding CPU's
L2/private DDR circular buffer, and every tenth local packet is also sent to
host memory.
