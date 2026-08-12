# Capture application

`test/capture.S` runs on hart 0 of the single Tribe cluster. It advances every
receive descriptor so RxRAM storage is released. A modulo-100 counter sends
only descriptor 100, 200, and so on through PacketDMA and the System RX queue.

`capture_20g_test` injects 200 unique minimum-IPG frames across the two 10GbE
interfaces, posts two host buffers, and checks that exactly two unique injected
packets arrive byte-for-byte with no network backpressure.
