# KlusterLab 2.0 UART diagnostics

These minimal XC7K325T images continuously transmit an ASCII banner on FPGA
pin A17 (`UART_USB_RxD`, the receive input of the on-board JTAG-SMT3 USB-UART)
at 115200 baud, 8 data bits, no parity, and one stop bit.  They do not contain
the SmartNIC, CPU, PCIe, Ethernet MAC/PCS, or any ILA/debug core.

Test `uart_diag_A17_sysclk.bit` first.  It derives the baud clock from the
200 MHz differential system oscillator on AC9/AD9.  If it is silent, test
`uart_diag_A17_ethclk.bit`, which derives the baud clock from the 156.25 MHz
Ethernet reference clock on H6/H5.  The images send different banners and
repeat them approximately once per second.

After programming an image, monitor both enumerated serial ports because their
Linux numbering depends on USB discovery order:

```sh
picocom -b 115200 /dev/ttyUSB0
picocom -b 115200 /dev/ttyUSB1
```

Expected text:

```text
KLUSTERLAB2 UART_USB_RXD A17 115200 8N1
KLUSTERLAB2 UART_USB_RXD A17 ETHCLK 8N1
```

To rebuild both images with Vivado 2026.1:

```sh
export XILINXD_LICENSE_FILE=/root/Xilinx.lic
/tools/2026.1/Vivado/bin/vivado -mode batch \
  -source fpga/diagnostics/build_uart_diagnostics.tcl
```

The schematic direction matters: K15 (`UART_USB_TxD`) and B17
(`UART_USB_RTS`) are outputs from the USB bridge and therefore FPGA inputs.
A17 (`UART_USB_RxD`) and F18 (`UART_USB_CTS`) are FPGA outputs.  Do not drive
K15 or B17 from FPGA logic.

## Standalone 10G UART probe

`uart_10g_probe.bit` is a separate hardware-diagnostic image containing both
KlusterLab 10G MAC/PCS instances, their shared QPLL/reset/clock topology, and
the 16 KiB UART capture buffer.  It deliberately omits CPU, PCIe, and SmartNIC
packet storage so it remains easy to route while diagnosing reference clock,
PLL lock, reset completion, PCS/PMA status, and the CDC clock counters.  Its
dump schema is `ETHD`; `fpga/uart_probe.py` selects the corresponding flag
names automatically.

Program the image, then run this on the UART host (only Python 3 is required):

```sh
python3 fpga/uart_probe.py --port /dev/ttyUSB1 \
  --output uart_probe_dump.bin --text uart_probe_dump.txt
```

Before a command, the FPGA transmits `UART_PROBE_READY` approximately once
per second. This is an independent heartbeat proving that the system
oscillator, startup MMCM/reset, UART clock, A17 pin, and host baud rate work.
Close `picocom` before running the Python downloader so it can own the port.

The host does not need Tcl, Vivado, Xilinx tools, or JTAG. It creates a modem
RTS transition on B17 as an out-of-band trigger and also sends the four bytes
`DUMP` on K15. Either path starts the same framed binary capture. The script
validates its CRC32 and writes the decoded report. Its initial two-second delay
establishes and flushes the RTS baseline before making the deliberate trigger
edge. If the script is copied away from the repository, copy only
`fpga/uart_probe.py`.

Because some boards do not deliver either bridge output to K15/B17, this image
also starts a dump autonomously after filling the capture buffer and repeats
it approximately every four seconds. The host decoder searches for the next
complete `UPRB` frame. Diagnostic flag bits report whether K15 or B17 ever
changed state, which separates a host-control problem from an FPGA parser
problem without requiring a working FPGA input path.

To rebuild the standalone image on the FPGA build machine:

```sh
export XILINXD_LICENSE_FILE=/root/Xilinx.lic
/tools/2026.1/Vivado/bin/vivado -mode batch \
  -source fpga/diagnostics/build_uart_10g_probe.tcl
```
