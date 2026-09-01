#!/usr/bin/env python3
"""Download and decode the KlusterLab UART 10G probe capture."""

from __future__ import annotations

import argparse
import binascii
import fcntl
import math
import os
import select
import statistics
import struct
import sys
import termios
import time
from collections import Counter
from pathlib import Path

MAGIC = b"UPRB"
TRAILER_MAGIC = b"END!"
HEADER_BYTES = 32
RECORD_BYTES = 16
RECORD = struct.Struct("<IHBB4H")

FLAG_NAMES = (
    "startup_locked",
    "startup_reset",
    "qpll_lock",
    "eth_reset_done",
    "eth_reset_counter_done",
    "eth_reset_from_ip",
    "design_reset",
    "pcie_link_up",
    "pcie_system_reset",
    "sfp_los0",
    "sfp_los1",
    "rx_error0_sticky",
    "rx_error1_sticky",
    "nic_protocol_error",
    "nic_storage_full",
    "system_protocol_error",
)

DIAGNOSTIC_FLAG_NAMES = (
    "startup_locked",
    "startup_reset",
    "qpll_lock",
    "eth_reset_done",
    "eth_reset_counter_done",
    "eth_reset_from_ip",
    "design_reset",
    "slave_tx_reset_done",
    "slave_rx_reset_done",
    "sfp_los0",
    "sfp_los1",
    "rx_error0_sticky",
    "rx_error1_sticky",
    "uart_k15_edge_seen",
    "pcs_tx_disable0",
    "pcs_tx_disable1",
)

SFP4_DIAGNOSTIC_FLAG_NAMES = (
    "startup_active",
    "startup_reset",
    "qpll_lock",
    "eth_reset_counter_done",
    "tx_reset_done0",
    "tx_reset_done1",
    "tx_reset_done2",
    "tx_reset_done3",
    "rx_reset_done0",
    "rx_reset_done1",
    "rx_reset_done2",
    "rx_reset_done3",
    "sfp_los0",
    "sfp_los1",
    "sfp_los2",
    "sfp_los3",
)

CLOCK_NAMES = (
    "net_clk",
    "txusrclk",
    "pcie_clk",
)

ACTIVITY_NAMES = ("rx0_words", "rx1_words", "tx0_words", "tx1_words")


def gray_to_binary(value: int) -> int:
    result = value
    shift = 1
    while shift < 16:
        result ^= result >> shift
        shift <<= 1
    return result & 0xFFFF


def gray4_to_binary(value: int) -> int:
    value &= 0xF
    value ^= value >> 1
    value ^= value >> 2
    return value & 0xF


def delta16(new: int, old: int) -> int:
    return (new - old) & 0xFFFF


def configure_uart(fd: int, baud: int) -> None:
    speeds = {
        115200: termios.B115200,
        57600: termios.B57600,
        38400: termios.B38400,
    }
    if baud not in speeds:
        raise ValueError(f"unsupported baud rate {baud}")
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CLOCAL | termios.CREAD | termios.CS8
    attrs[3] = 0
    attrs[4] = speeds[baud]
    attrs[5] = speeds[baud]
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)


def trigger_with_rts(fd: int) -> bool:
    """Create a deliberate edge on the SMT3 RTS/B17 fallback trigger."""
    required = ("TIOCMBIC", "TIOCMBIS", "TIOCM_RTS")
    if not all(hasattr(termios, name) for name in required):
        return False
    mask = struct.pack("I", termios.TIOCM_RTS)
    try:
        # Establish a baseline. If this transition started a stale dump, two
        # seconds lets the maximum 16 KiB response finish before it is flushed.
        fcntl.ioctl(fd, termios.TIOCMBIC, mask)
        time.sleep(2.0)
        termios.tcflush(fd, termios.TCIFLUSH)
        fcntl.ioctl(fd, termios.TIOCMBIS, mask)
        return True
    except OSError:
        return False


def read_some(fd: int, timeout_at: float) -> bytes:
    remaining = timeout_at - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("UART probe response timed out")
    readable, _, _ = select.select([fd], [], [], remaining)
    if not readable:
        raise TimeoutError("UART probe response timed out")
    return os.read(fd, 4096)


def read_exact(fd: int, size: int, timeout_at: float) -> bytes:
    result = bytearray()
    while len(result) < size:
        chunk = read_some(fd, timeout_at)
        if chunk:
            result.extend(chunk)
    return bytes(result)


def pop_complete_frame(stream: bytearray) -> bytes | None:
    """Extract one valid frame while preserving arbitrary read-ahead bytes."""
    while True:
        position = stream.find(MAGIC)
        if position < 0:
            # Retain only a possible split magic prefix between OS reads.
            del stream[:-len(MAGIC) + 1]
            return None
        if position:
            del stream[:position]
        if len(stream) < HEADER_BYTES:
            return None

        version, header_size, record_size = stream[4], stream[5], stream[6]
        count = struct.unpack_from("<I", stream, 8)[0]
        depth = struct.unpack_from("<I", stream, 24)[0]
        if (version != 1 or header_size != HEADER_BYTES
                or record_size != RECORD_BYTES or depth == 0
                or count > depth or depth > 1_048_576):
            # This was an accidental UPRB sequence in stale payload/noise.
            del stream[0]
            continue

        frame_size = header_size + count * record_size + 8
        if len(stream) < frame_size:
            return None
        candidate = bytes(stream[:frame_size])
        payload = candidate[header_size:-8]
        trailer = candidate[-8:]
        expected_crc = struct.unpack_from("<I", trailer, 4)[0]
        if (trailer[:4] != TRAILER_MAGIC
                or (binascii.crc32(payload) & 0xFFFFFFFF) != expected_crc):
            del stream[0]
            continue
        del stream[:frame_size]
        return candidate


def capture(port: str, baud: int, timeout: float, initiate: bool = True) -> bytes:
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_SYNC)
    try:
        configure_uart(fd, baud)
        if initiate:
            trigger_with_rts(fd)
            # A leading delimiter resets any partial command left by line
            # noise. Repetition is harmless once a dump starts and makes
            # command delivery robust across a UART open/configure boundary.
            os.write(fd, b"\rDUMPDUMPDUMP")
        deadline = time.monotonic() + timeout

        # Search a persistent stream buffer. A single OS read normally contains
        # UPRB plus part of its header/payload, so framing must not depend on
        # UPRB landing at the end of that read.
        stream = bytearray()
        tail = bytearray()
        saw_heartbeat = False
        try:
            while True:
                chunk = read_some(fd, deadline)
                if not chunk:
                    continue
                tail.extend(chunk)
                if len(tail) > 64:
                    del tail[:-64]
                stream.extend(chunk)
                saw_heartbeat |= b"UART_PROBE_READY" in stream
                frame = pop_complete_frame(stream)
                if frame is not None:
                    return frame
        except TimeoutError as error:
            if saw_heartbeat:
                if initiate:
                    raise TimeoutError(
                        "UART heartbeat received, but neither the RTS/B17 nor "
                        "DUMP/K15 trigger was accepted"
                    ) from error
                raise TimeoutError(
                    "UART heartbeat received, but no packet-triggered dump "
                    "arrived before the timeout"
                ) from error
            if tail:
                preview = bytes(tail).decode("ascii", errors="replace")
                raise TimeoutError(
                    f"UART data received but no UPRB frame; tail={preview!r}"
                ) from error
            raise TimeoutError(
                "no UART heartbeat or dump response received"
            ) from error
    finally:
        os.close(fd)


def parse_dump(data: bytes) -> tuple[dict[str, int | str], list[dict[str, int]]]:
    if len(data) < HEADER_BYTES + 8 or data[:4] != MAGIC:
        raise ValueError("not a UART probe dump (UPRB magic missing)")
    version, header_size, record_size, flags = data[4:8]
    count, sample_div, clock_hz, sequence, depth = struct.unpack_from(
        "<5I", data, 8
    )
    schema = data[28:32].decode("ascii", errors="replace")
    expected_size = header_size + count * record_size + 8
    if version != 1 or header_size != HEADER_BYTES or record_size != RECORD_BYTES:
        raise ValueError(
            f"unsupported format version={version} header={header_size} "
            f"record={record_size}"
        )
    if len(data) != expected_size:
        raise ValueError(f"dump length {len(data)} != expected {expected_size}")
    payload = data[header_size : header_size + count * record_size]
    trailer = data[-8:]
    if trailer[:4] != TRAILER_MAGIC:
        raise ValueError("UART probe END! trailer missing")
    expected_crc = struct.unpack_from("<I", trailer, 4)[0]
    actual_crc = binascii.crc32(payload) & 0xFFFFFFFF
    if actual_crc != expected_crc:
        raise ValueError(
            f"payload CRC mismatch: got {actual_crc:08x}, expected {expected_crc:08x}"
        )

    records: list[dict[str, int]] = []
    if schema == "PLBK":
        for offset in range(0, len(payload), RECORD_BYTES):
            raw = payload[offset : offset + RECORD_BYTES]
            engine = struct.unpack_from("<I", raw, 10)[0]
            record = {
                "timestamp": struct.unpack_from("<I", raw, 0)[0],
                "destination_mac": int.from_bytes(raw[4:10], "little"),
                "engine": engine,
                "system_status": struct.unpack_from("<H", raw, 14)[0],
            }
            records.append(record)
    elif schema == "PCPU":
        for values in RECORD.iter_unpack(payload):
            (timestamp, state_flags, dma_status, event,
             descriptors, rx_words, tx_words, tx_packets) = values
            records.append({
                "timestamp": timestamp,
                "flags": state_flags,
                "dma_status": dma_status,
                "event": event,
                "descriptors": descriptors,
                "rx_words": rx_words,
                "tx_words": tx_words,
                "tx_packets": tx_packets,
            })
    elif schema == "PCRL":
        for offset in range(0, len(payload), RECORD_BYTES):
            raw = payload[offset : offset + RECORD_BYTES]
            packed = int.from_bytes(raw[4:16], "little")
            state_flags = packed & 0xFFFF
            packed >>= 16
            dma_status = packed & 0xFF
            packed >>= 8
            release_count = packed & 0xFF
            packed >>= 8
            release_handle = packed & 0x1FFFF
            packed >>= 17
            release_length = packed & 0x3FFF
            packed >>= 14
            used_rows = packed & 0x7FFF
            packed >>= 15
            release_row = packed & 0x3FFF
            records.append({
                "timestamp": struct.unpack_from("<I", raw, 0)[0],
                "flags": state_flags,
                "dma_status": dma_status,
                "event": release_count,
                "release_handle": release_handle,
                "release_length": release_length,
                "used_rows": used_rows,
                "release_row": release_row,
            })
    elif schema in ("SFPD", "SF4D"):
        sfp_record = struct.Struct("<IHBBBHHHB")
        for values in sfp_record.iter_unpack(payload):
            (timestamp, state_flags, pcs_status, meta, identifier,
             tx_bias, tx_power, rx_power, sfp_status) = values
            records.append({
                "timestamp": timestamp,
                "flags": state_flags,
                "pcs_status": pcs_status,
                "port": (meta >> 7) & 1,
                "diag_done": (meta >> 6) & 1,
                "mux_found": (meta >> 5) & 1,
                "port_valid": (meta >> 4) & 1,
                "mux_address": 0x70 | (meta & 0xf),
                "identifier": identifier,
                "tx_bias": tx_bias,
                "tx_power": tx_power,
                "rx_power": rx_power,
                "sfp_status": sfp_status,
            })
    else:
        for values in RECORD.iter_unpack(payload):
            timestamp, state_flags, status0, status1, *raw_fields = values
            record = {
                "timestamp": timestamp,
                "flags": state_flags,
                "status0": status0,
                "status1": status1,
                "activity": raw_fields[-1],
            }
            for name, raw in zip(CLOCK_NAMES, raw_fields[:-1]):
                record[name] = gray_to_binary(raw)
            activity = raw_fields[-1]
            for index, name in enumerate(ACTIVITY_NAMES):
                record[name] = gray4_to_binary(activity >> (index * 4))
            records.append(record)

    metadata: dict[str, int | str] = {
        "version": version,
        "flags": flags,
        "count": count,
        "sample_div": sample_div,
        "clock_hz": clock_hz,
        "sequence": sequence,
        "depth": depth,
        "schema": schema,
        "crc32": f"{actual_crc:08x}",
    }
    return metadata, records


def stable_bit(records: list[dict[str, int]], bit: int) -> str:
    ones = sum((record["flags"] >> bit) & 1 for record in records)
    if not records:
        return "n/a"
    if ones == len(records):
        return "1 (100%)"
    if ones == 0:
        return "0 (0%)"
    return f"mixed ({100.0 * ones / len(records):.1f}% high)"


LOOPBACK_ENGINE_BITS = (
    "rx_valid", "rx_ready", "rx_sop", "rx_eop",
    "tx0_valid", "tx0_ready", "tx1_valid", "tx1_ready",
    "job_pending", "rx_read_ready", "descriptor_valid",
    "descriptor_ready", "stream_active", "descriptor_active",
    "source_port", "destination_port",
)

LOOPBACK_STATUS_BITS = (
    "startup_locked", "qpll_lock", "eth_reset_done",
    "eth_reset_counter_done", "eth_reset_from_ip", "design_reset",
    "pause_rx_sfp2_sticky", "pause_rx_sfp3_sticky",
    "rx_error_sfp2_sticky", "rx_error_sfp3_sticky",
    "nic_protocol_error", "nic_storage_full",
    "pcs_link_sfp2", "pcs_link_sfp3",
    "pause_tx_sfp2_sticky", "pause_tx_sfp3_sticky",
)


def format_mac(value: int) -> str:
    return ":".join(f"{(value >> (8 * byte)) & 0xff:02x}" for byte in range(6))


def render_loopback_text(
    metadata: dict[str, int | str], records: list[dict[str, int]]
) -> str:
    clock_hz = int(metadata["clock_hz"])
    origin = records[0]["timestamp"] if records else 0
    active = [
        record for record in records
        if record["engine"] & ((1 << 0) | (1 << 2) | (1 << 3)
                               | (1 << 4) | (1 << 6) | (1 << 8)
                               | (1 << 10) | (1 << 28) | (1 << 30))
    ]
    transfers = [
        record for record in records
        if (record["engine"] & 0x3) == 0x3
    ]
    sops = [record for record in transfers if record["engine"] & (1 << 2)]
    eops = [record for record in transfers if record["engine"] & (1 << 3)]
    stalls = [
        record for record in records
        if (record["engine"] & 1) and not (record["engine"] & 2)
    ]
    descriptor_words = [
        record for record in records
        if (record["engine"] & (1 << 10))
        and (record["engine"] & (1 << 11))
    ]
    rxram_commands = [
        record for record in records
        if (record["engine"] & (1 << 8))
        and (record["engine"] & (1 << 9))
    ]
    txfifo_words = [
        record for record in records
        if ((record["engine"] & (3 << 4)) == (3 << 4))
        or ((record["engine"] & (3 << 6)) == (3 << 6))
    ]
    mac0_words = [
        record for record in records
        if (record["engine"] & (3 << 28)) == (3 << 28)
    ]
    mac1_words = [
        record for record in records
        if (record["engine"] & (3 << 30)) == (3 << 30)
    ]
    errors = [
        record for record in records
        if (record["engine"] & (1 << 26))
        or (record["system_status"] & ((1 << 8) | (1 << 9)
                                       | (1 << 10) | (1 << 11)))
    ]
    routes = Counter(
        ((record["engine"] >> 14) & 1, (record["engine"] >> 15) & 1)
        for record in transfers
    )

    lines = [
        "KlusterLab packet loopback UART probe",
        f"schema={metadata['schema']} sequence={metadata['sequence']} "
        f"records={metadata['count']}/{metadata['depth']} crc32={metadata['crc32']}",
        f"sample_clock={clock_hz} Hz sample_div={metadata['sample_div']} "
        f"period={1e9 * int(metadata['sample_div']) / clock_hz:.3f} ns",
        "",
        "Loopback summary:",
        f"  RxFifo descriptor words  {len(descriptor_words)}",
        f"  RxRAM read commands      {len(rxram_commands)}",
        f"  RxRAM accepted words     {len(transfers)}",
        f"  TxFifo accepted words    {len(txfifo_words)}",
        f"  MAC0/SFP2 accepted words {len(mac0_words)}",
        f"  MAC1/SFP3 accepted words {len(mac1_words)}",
        f"  accepted packet starts   {len(sops)}",
        f"  accepted packet ends     {len(eops)}",
        f"  backpressured RX cycles  {len(stalls)}",
        f"  protocol/status errors   {len(errors)}",
    ]
    for route, count in sorted(routes.items()):
        lines.append(f"  route port {route[0]} -> {route[1]}       {count} words")
    if sops:
        lines.append(f"  first destination MAC    {format_mac(sops[0]['destination_mac'])}")

    latest_status = records[-1]["system_status"] if records else 0
    lines.extend(("", "System status at end of capture:"))
    for bit, name in enumerate(LOOPBACK_STATUS_BITS):
        lines.append(f"  {name:24s} {(latest_status >> bit) & 1}")

    clocks_good = bool(latest_status & (1 << 0)) and bool(
        latest_status & (1 << 1))
    ethernet_good = all(latest_status & (1 << bit) for bit in (2, 3, 12, 13))
    pause_received = latest_status & ((1 << 6) | (1 << 7))
    pause_transmitted = latest_status & ((1 << 14) | (1 << 15))
    txfifo_match = bool(transfers) and len(txfifo_words) == len(transfers)
    mac_output = bool(mac0_words or mac1_words)
    route_good = bool(routes) and all(source != destination for source, destination in routes)
    lines.extend((
        "",
        "Automatic checks:",
        f"  startup/refclk/QPLL       {'GOOD' if clocks_good else 'BAD'}",
        f"  Ethernet reset/PCS links  {'GOOD' if ethernet_good else 'BAD'}",
        f"  MAC pause received        {'YES' if pause_received else 'NO'}",
        f"  MAC pause transmitted     {'YES' if pause_transmitted else 'NO'}",
        f"  RxRAM/TxFifo beat match   {'GOOD' if txfifo_match else 'BAD'}",
        f"  MAC transmit observed     {'GOOD' if mac_output else 'BAD'}",
        f"  packet RX observed        {'GOOD' if transfers and sops and eops else 'BAD'}",
        f"  channel swap              {'GOOD' if route_good else 'BAD'}",
        f"  protocol/error flags      {'GOOD' if not errors else 'BAD'}",
        "",
        "Packet/engine event samples:",
        "time_us mac               engine   word src dst DV/R JV/R RV/RR S E F0V/R F1V/R M0V/R M1V/R",
    ))
    for record in active:
        engine = record["engine"]
        elapsed = ((record["timestamp"] - origin) & 0xffffffff) / clock_hz * 1e6
        lines.append(
            f"{elapsed:8.3f} {format_mac(record['destination_mac'])} "
            f"{engine:08x} {(engine >> 16) & 0x3ff:4d} "
            f"{(engine >> 14) & 1}   {(engine >> 15) & 1}   "
            f"{(engine >> 10) & 1}/{(engine >> 11) & 1}  "
            f"{(engine >> 8) & 1}/{(engine >> 9) & 1}  "
            f"{(engine >> 0) & 1}/{(engine >> 1) & 1}  "
            f"{(engine >> 2) & 1} {((engine >> 3) & 1)}  "
            f"{(engine >> 4) & 1}/{(engine >> 5) & 1}   "
            f"{(engine >> 6) & 1}/{(engine >> 7) & 1}   "
            f"{(engine >> 28) & 1}/{(engine >> 29) & 1}   "
            f"{(engine >> 30) & 1}/{(engine >> 31) & 1}"
        )
    return "\n".join(lines) + "\n"


def render_text(metadata: dict[str, int | str], records: list[dict[str, int]]) -> str:
    if metadata["schema"] == "PLBK":
        return render_loopback_text(metadata, records)
    if metadata["schema"] == "PCPU":
        return render_cpu_processing_text(metadata, records)
    if metadata["schema"] == "PCRL":
        return render_cpu_release_text(metadata, records)
    if metadata["schema"] in ("SFPD", "SF4D"):
        return render_sfp_diagnostic_text(metadata, records)
    diagnostic = metadata["schema"] == "ETHD"
    flag_names = DIAGNOSTIC_FLAG_NAMES if diagnostic else FLAG_NAMES
    lines = [
        "KlusterLab UART 10G probe",
        f"schema={metadata['schema']} sequence={metadata['sequence']} "
        f"records={metadata['count']}/{metadata['depth']} crc32={metadata['crc32']}",
        f"sample_clock={metadata['clock_hz']} Hz sample_div={metadata['sample_div']} "
        f"period={1e6 * int(metadata['sample_div']) / int(metadata['clock_hz']):.3f} us",
        "",
        "State flags:",
    ]
    for bit, name in enumerate(flag_names):
        lines.append(f"  {name:24s} {stable_bit(records, bit)}")

    lines.extend(("", "Most common PCS/PMA status:"))
    for lane in (0, 1):
        values = Counter(record[f"status{lane}"] for record in records)
        common = values.most_common(3)
        text = ", ".join(f"0x{value:02x} ({count})" for value, count in common)
        lines.append(f"  lane{lane}: {text or 'n/a'}")

    if len(records) >= 2:
        intervals = []
        for old, new in zip(records, records[1:]):
            cycles = (new["timestamp"] - old["timestamp"]) & 0xFFFFFFFF
            if cycles:
                intervals.append((old, new, cycles / int(metadata["clock_hz"])))

        lines.extend(("", "Measured clocks (median):"))
        for name in CLOCK_NAMES:
            mhz = [
                delta16(new[name], old[name]) / seconds / 1e6
                for old, new, seconds in intervals
            ]
            lines.append(f"  {name:24s} {statistics.median(mhz):9.4f} MHz")

        activity_title = (
            "Observed RX-valid and TX-ready activity during capture:"
            if diagnostic else "Observed transfers during capture:"
        )
        lines.extend(("", activity_title))
        for name in ACTIVITY_NAMES:
            total = sum((new[name] - old[name]) & 0xF for old, new, _ in intervals)
            lines.append(f"  {name:24s} {total}")

        qpll_good = all((record["flags"] >> 2) & 1 for record in records)
        reset_good = all((record["flags"] >> 3) & 1 for record in records)
        signal_good = all(
            not (record["flags"] & ((1 << 9) | (1 << 10)))
            for record in records
        )
        lane0_good = all(record["status0"] & 1 for record in records)
        lane1_good = all(record["status1"] & 1 for record in records)
        rx_error_good = all(
            not (record["flags"] & ((1 << 11) | (1 << 12)))
            for record in records
        )
        txusr_mhz = statistics.median(
            delta16(new["txusrclk"], old["txusrclk"]) / seconds / 1e6
            for old, new, seconds in intervals
        )
        net_mhz = statistics.median(
            delta16(new["net_clk"], old["net_clk"]) / seconds / 1e6
            for old, new, seconds in intervals
        )
        ref_good = 150.0 <= net_mhz <= 162.0
        # The 7-series 10G PCS/PMA metadata specifies both txusrclk outputs at
        # 322.265625 MHz. net_clk is the separate 156.25 MHz MAC/core clock.
        txusr_good = 315.0 <= txusr_mhz <= 330.0
        lines.extend(
            (
                "",
                "Automatic checks:",
                f"  10G reference-derived clock {'GOOD' if ref_good else 'BAD'} "
                f"({net_mhz:.4f} MHz, expected 156.25 MHz)",
                f"  QPLL lock                  {'GOOD' if qpll_good else 'BAD'}",
                f"  Ethernet reset done        {'GOOD' if reset_good else 'BAD'}",
                f"  TX user clock / CDC         {'GOOD' if txusr_good else 'BAD'} "
                f"({txusr_mhz:.4f} MHz, expected 322.265625 MHz)",
                f"  SFP signal detect           {'GOOD' if signal_good else 'BAD'}",
                f"  PCS lane 0 block lock       {'GOOD' if lane0_good else 'BAD'}",
                f"  PCS lane 1 block lock       {'GOOD' if lane1_good else 'BAD'}",
                f"  RX error sticky flags       {'GOOD' if rx_error_good else 'BAD'}",
            )
        )

    lines.extend(
        (
            "",
            "Samples:",
            "time_ms flags sts0 sts1 net txusr pcie rx0 rx1 tx0 tx1 activity_gray",
        )
    )
    clock_hz = int(metadata["clock_hz"])
    origin = records[0]["timestamp"] if records else 0
    for record in records:
        elapsed = ((record["timestamp"] - origin) & 0xFFFFFFFF) / clock_hz * 1e3
        lines.append(
            f"{elapsed:7.3f} {record['flags']:04x} {record['status0']:02x} "
            f"{record['status1']:02x} "
            + " ".join(str(record[name]) for name in CLOCK_NAMES + ACTIVITY_NAMES)
            + f" {record['activity']:04x}"
        )
    return "\n".join(lines) + "\n"


CPU_PROCESSING_FLAG_NAMES = (
    "startup_locked", "qpll_lock", "pcs_link_sfp2", "pcs_link_sfp3",
    "descriptor_valid", "descriptor_ready", "rxram_command_valid",
    "rxram_command_ready", "rxram_data_valid", "rxram_data_ready",
    "packetdma_tx_valid", "packetdma_tx_ready", "packetdma_busy",
    "packetdma_error", "descriptor_fetcher_error", "network_error",
)


def counter_delta(records: list[dict[str, int]], name: str) -> int:
    if len(records) < 2:
        return 0
    return sum(
        (new[name] - old[name]) & 0xFFFF
        for old, new in zip(records, records[1:])
    )


def render_cpu_processing_text(
    metadata: dict[str, int | str], records: list[dict[str, int]]
) -> str:
    latest = records[-1] if records else {
        "flags": 0, "dma_status": 0, "descriptors": 0,
        "rx_words": 0, "tx_words": 0, "tx_packets": 0,
    }
    descriptors = counter_delta(records, "descriptors")
    rx_words = counter_delta(records, "rx_words")
    tx_words = counter_delta(records, "tx_words")
    tx_packets = counter_delta(records, "tx_packets")
    error_mask = (1 << 13) | (1 << 14) | (1 << 15)
    errors = any(record["flags"] & error_mask for record in records)
    links_good = bool((latest["flags"] & 0xF) == 0xF)
    # A command-driven dump is commonly requested after traffic has stopped.
    # Counter movement inside the 102.4 ms capture window proves live traffic,
    # while nonzero lifetime counters still prove that the CPU/DMA datapath
    # forwarded packets since reset. Do not report that valid post-traffic
    # state as BAD merely because the circular capture is quiescent.
    progress_in_window = descriptors > 0 and rx_words > 0 and tx_words > 0 \
        and tx_packets > 0
    lifetime_progress = latest["descriptors"] > 0 \
        and latest["rx_words"] > 0 and latest["tx_words"] > 0 \
        and latest["tx_packets"] > 0
    progress_good = progress_in_window or lifetime_progress
    pause_seen = [
        any(record["dma_status"] & (1 << (4 + stream)) for record in records)
        for stream in range(2)
    ]
    pause_active = [
        bool(latest["dma_status"] & (1 << (4 + stream)))
        for stream in range(2)
    ]
    lines = [
        "KlusterLab real Processing/CPU UART probe",
        f"schema={metadata['schema']} sequence={metadata['sequence']} "
        f"records={metadata['count']}/{metadata['depth']} crc32={metadata['crc32']}",
        f"sample_clock={metadata['clock_hz']} Hz "
        f"sample_div={metadata['sample_div']} "
        f"period={1e6 * int(metadata['sample_div']) / int(metadata['clock_hz']):.3f} us",
        "",
        "State flags:",
    ]
    for bit, name in enumerate(CPU_PROCESSING_FLAG_NAMES):
        lines.append(f"  {name:28s} {stable_bit(records, bit)}")
    lines.extend((
        "",
        "Observed counter changes in capture window:",
        f"  completed descriptors        {descriptors}",
        f"  accepted RxRAM words         {rx_words}",
        f"  accepted PacketDMA TX words  {tx_words}",
        f"  completed TX packets         {tx_packets}",
        "",
        "Lifetime counters at final sample:",
        f"  completed descriptors        {latest['descriptors']}",
        f"  accepted RxRAM words         {latest['rx_words']}",
        f"  accepted PacketDMA TX words  {latest['tx_words']}",
        f"  completed TX packets         {latest['tx_packets']}",
        f"  RxRAM release events (mod 256) {latest['event']}",
        f"  DMA error reason             {latest['dma_status'] & 0xF}",
        f"  RxRAM PAUSE pressure port 0  "
        f"{'ACTIVE' if pause_active[0] else ('seen/recovered' if pause_seen[0] else 'clear')}",
        f"  RxRAM PAUSE pressure port 1  "
        f"{'ACTIVE' if pause_active[1] else ('seen/recovered' if pause_seen[1] else 'clear')}",
        "",
        "Automatic checks:",
        f"  startup/QPLL/PCS links       {'GOOD' if links_good else 'BAD'}",
        f"  CPU/DMA forwarding progress  {'GOOD' if progress_good else 'BAD'}",
        f"  protocol/error flags         {'GOOD' if not errors else 'BAD'}",
        "",
        "Samples:",
        "time_ms flags dma releases descriptors rx_words tx_words tx_packets",
    ))
    clock_hz = int(metadata["clock_hz"])
    origin = records[0]["timestamp"] if records else 0
    for record in records:
        elapsed = ((record["timestamp"] - origin) & 0xFFFFFFFF) \
            / clock_hz * 1e3
        lines.append(
            f"{elapsed:9.3f} {record['flags']:04x} "
            f"{record['dma_status']:02x} {record['event']:02x} "
            f"{record['descriptors']:5d} {record['rx_words']:5d} "
            f"{record['tx_words']:5d} {record['tx_packets']:5d}"
        )
    return "\n".join(lines) + "\n"


def render_cpu_release_text(
    metadata: dict[str, int | str], records: list[dict[str, int]]
) -> str:
    latest = records[-1] if records else {
        "flags": 0, "dma_status": 0, "event": 0,
        "release_handle": 0, "release_length": 0,
        "used_rows": 0, "release_row": 0,
    }
    handle = latest["release_handle"]
    length = latest["release_length"]
    start_row = handle >> 3
    released_rows = ((length + 31) // 32) * 4 if length else 0
    expected_row = (start_row + released_rows) & 0x3FFF
    allocator_match = bool(length) and latest["release_row"] == expected_row
    stream = handle & 7
    pause_active = stream < 2 and bool(
        latest["dma_status"] & (1 << (4 + stream)))
    rxram_protocol_error = bool(latest["dma_status"] & (1 << 7))
    rxram_storage_full = bool(latest["dma_status"] & (1 << 6))
    error_mask = (1 << 13) | (1 << 14) | (1 << 15)
    errors = any(record["flags"] & error_mask for record in records)
    links_good = bool((latest["flags"] & 0xF) == 0xF)

    lines = [
        "KlusterLab CPU/RxRAM release diagnostic",
        f"schema={metadata['schema']} sequence={metadata['sequence']} "
        f"records={metadata['count']}/{metadata['depth']} crc32={metadata['crc32']}",
        f"sample_clock={metadata['clock_hz']} Hz "
        f"sample_div={metadata['sample_div']} "
        f"period={1e6 * int(metadata['sample_div']) / int(metadata['clock_hz']):.3f} us",
        "",
        "State flags:",
    ]
    for bit, name in enumerate(CPU_PROCESSING_FLAG_NAMES):
        lines.append(f"  {name:28s} {stable_bit(records, bit)}")
    lines.extend((
        "",
        "Release/allocator state at final sample:",
        f"  release events (mod 256)     {latest['event']}",
        f"  last handle                  0x{handle:05x}",
        f"  last stream                  {stream}",
        f"  last start row               {start_row}",
        f"  last length                  {length} bytes",
        f"  rows represented by release {released_rows}",
        f"  expected next release row    {expected_row}",
        f"  actual next release row      {latest['release_row']}",
        f"  occupied selected rows       {latest['used_rows']}",
        f"  selected stream PAUSE        {'ACTIVE' if pause_active else 'clear'}",
        f"  RxRAM protocol error         {'ACTIVE' if rxram_protocol_error else 'clear'}",
        f"  RxRAM storage full           {'ACTIVE' if rxram_storage_full else 'clear'}",
        f"  DMA error reason             {latest['dma_status'] & 0xF}",
        "",
        "Automatic checks:",
        f"  startup/QPLL/PCS links       {'GOOD' if links_good else 'BAD'}",
        f"  last release was applied     {'GOOD' if allocator_match else 'BAD'}",
        f"  allocator drained after idle {'GOOD' if latest['used_rows'] == 0 else 'BAD'}",
        f"  protocol/error flags         {'GOOD' if not errors else 'BAD'}",
        "",
        "Samples:",
        "time_ms flags dma count handle length used release_row",
    ))
    clock_hz = int(metadata["clock_hz"])
    origin = records[0]["timestamp"] if records else 0
    previous = None
    for record in records:
        state = (
            record["flags"], record["dma_status"], record["event"],
            record["release_handle"], record["release_length"],
            record["used_rows"], record["release_row"],
        )
        if state == previous:
            continue
        previous = state
        elapsed = ((record["timestamp"] - origin) & 0xFFFFFFFF) \
            / clock_hz * 1e3
        lines.append(
            f"{elapsed:9.3f} {record['flags']:04x} "
            f"{record['dma_status']:02x} {record['event']:3d} "
            f"{record['release_handle']:05x} {record['release_length']:5d} "
            f"{record['used_rows']:5d} {record['release_row']:5d}"
        )
    return "\n".join(lines) + "\n"


def optical_dbm(raw: int) -> str:
    milliwatts = raw * 0.0001
    if milliwatts <= 0:
        return "no measurable power"
    return f"{10.0 * math.log10(milliwatts):.2f} dBm ({milliwatts:.4f} mW)"


def render_sfp_diagnostic_text(
    metadata: dict[str, int | str], records: list[dict[str, int]]
) -> str:
    lines = [
        "KlusterLab FPGA-TX/SFP diagnostic",
        f"schema={metadata['schema']} sequence={metadata['sequence']} "
        f"records={metadata['count']}/{metadata['depth']} crc32={metadata['crc32']}",
        "",
        "FPGA 10G state flags:",
    ]
    all_cages = metadata["schema"] == "SF4D"
    flag_names = SFP4_DIAGNOSTIC_FLAG_NAMES if all_cages else DIAGNOSTIC_FLAG_NAMES
    for bit, name in enumerate(flag_names):
        lines.append(f"  {name:24s} {stable_bit(records, bit)}")

    lines.extend(("", "SFP management/DDM:"))
    port_results: dict[int, dict[str, int]] = {}
    for record in records:
        if record["diag_done"]:
            port_results[record["port"]] = record
    for port in (0, 1):
        record = port_results.get(port)
        if record is None:
            lines.append(f"  port {port}: no completed diagnostic record")
            continue
        lines.extend((
            f"  port {port}:",
            f"    mux                     "
            f"{'found' if record['mux_found'] else 'NOT FOUND'} at "
            f"0x{record['mux_address']:02x}",
            f"    SFP EEPROM/DDM valid    {record['port_valid']}",
            f"    identifier              0x{record['identifier']:02x} "
            f"({'SFP/SFP+' if record['identifier'] == 3 else 'unexpected'})",
            f"    TX laser bias           {record['tx_bias'] * 0.002:.3f} mA "
            f"(raw 0x{record['tx_bias']:04x})",
            f"    TX optical power        {optical_dbm(record['tx_power'])} "
            f"(raw 0x{record['tx_power']:04x})",
            f"    RX optical power        {optical_dbm(record['rx_power'])} "
            f"(raw 0x{record['rx_power']:04x})",
            f"    status/control          0x{record['sfp_status']:02x} "
            f"(tx_disable={(record['sfp_status'] >> 7) & 1}, "
            f"tx_fault={(record['sfp_status'] >> 2) & 1}, "
            f"rx_los={(record['sfp_status'] >> 1) & 1})",
            f"    PCS/PMA status          0x{record['pcs_status']:02x}",
        ))

    tx_good = bool(port_results) and all(
        value["port_valid"] and value["identifier"] == 3
        and value["tx_bias"] != 0 and value["tx_power"] != 0
        and not (value["sfp_status"] & ((1 << 7) | (1 << 2)))
        for value in port_results.values()
    ) and len(port_results) == 2
    if all_cages:
        gt_good = bool(records) and all(
            (record["flags"] & 0xFFFC) == 0x0FFC
            for record in records
        )
        lines.extend((
            "",
            "Four-cage GTX check:",
            f"  QPLL and all TX/RX resets {'GOOD' if gt_good else 'BAD'}",
            f"  optical signal all cages  {'GOOD' if gt_good else 'BAD/INCOMPLETE'}",
        ))
    lines.extend((
        "",
        "Automatic FPGA-TX check:",
        f"  both SFP lasers active    {'GOOD' if tx_good else 'BAD/INCOMPLETE'}",
        "  interpretation            "
        + ("optical modules are transmitting; investigate GTX electrical "
           "signal/encoding next" if tx_good else
           "resolve module enable/fault/power before further GTX emphasis sweeps"),
    ))
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--port", help="UART device, normally /dev/ttyUSB1")
    source.add_argument("--input", type=Path, help="decode an existing binary dump")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument(
        "--wait-trigger",
        action="store_true",
        help="do not send RTS/DUMP; wait for the FPGA packet trigger",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("uart_probe_dump.bin"),
        help="binary capture output (capture mode only)",
    )
    parser.add_argument(
        "--text",
        nargs="?",
        const="-",
        metavar="FILE",
        help="also decode to text; without FILE, write text to stdout",
    )
    args = parser.parse_args()

    if args.port:
        data = capture(args.port, args.baud, args.timeout,
                       initiate=not args.wait_trigger)
        args.output.write_bytes(data)
        print(f"saved {len(data)} bytes to {args.output}", file=sys.stderr)
    else:
        data = args.input.read_bytes()

    metadata, records = parse_dump(data)
    if args.text is not None:
        report = render_text(metadata, records)
        if args.text == "-":
            sys.stdout.write(report)
        else:
            Path(args.text).write_text(report)
            print(f"saved text report to {args.text}", file=sys.stderr)
    elif args.input:
        print(
            f"valid {metadata['schema']} dump: {metadata['count']} records, "
            f"CRC32 {metadata['crc32']}"
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, TimeoutError, ValueError) as error:
        print(f"uart_probe: {error}", file=sys.stderr)
        raise SystemExit(1)
