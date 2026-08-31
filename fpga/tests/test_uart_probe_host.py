#!/usr/bin/env python3

import binascii
import importlib.util
import struct
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "uart_probe.py"
SPEC = importlib.util.spec_from_file_location("uart_probe", MODULE_PATH)
uart_probe = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(uart_probe)


def binary_to_gray(value: int) -> int:
    return value ^ (value >> 1)


def make_dump(schema: bytes = b"ETH2") -> bytes:
    header = bytearray(32)
    header[:8] = b"UPRB\x01\x20\x10\x03"
    struct.pack_into("<5I", header, 8, 2, 5000, 50_000_000, 7, 1024)
    header[28:32] = schema
    fields0 = [100, 100, 80]
    fields1 = [15725, 32326, 12580]
    record0 = struct.pack(
        "<IHBB4H",
        10_000,
        0x009D,
        0x01,
        0x01,
        *(binary_to_gray(value) for value in fields0),
        0x0531,
    )
    record1 = struct.pack(
        "<IHBB4H",
        15_000,
        0x009D,
        0x01,
        0x01,
        *(binary_to_gray(value) for value in fields1),
        0x1A72,
    )
    payload = record0 + record1
    trailer = b"END!" + struct.pack("<I", binascii.crc32(payload) & 0xFFFFFFFF)
    return bytes(header) + payload + trailer


def make_loopback_dump() -> bytes:
    header = bytearray(32)
    header[:8] = b"UPRB\x01\x20\x10\x03"
    struct.pack_into("<5I", header, 8, 2, 1, 156_250_000, 3, 1024)
    header[28:32] = b"PLBK"
    status = 0x300F
    # source=0, destination=1, stream word=0, accepted SOP
    engine0 = 0x00008000 | 0x00000007 | 0x000000C0
    # source=0, destination=1, stream word=1, accepted EOP
    engine1 = 0x00018000 | 0x0000000B | 0x000000C0
    records = []
    for timestamp, engine in ((100, engine0), (101, engine1)):
        record = bytearray(16)
        struct.pack_into("<I", record, 0, timestamp)
        record[4:10] = bytes.fromhex("001122334455")
        struct.pack_into("<I", record, 10, engine)
        struct.pack_into("<H", record, 14, status)
        records.append(bytes(record))
    payload = b"".join(records)
    return (bytes(header) + payload + b"END!"
            + struct.pack("<I", binascii.crc32(payload) & 0xffffffff))


def make_cpu_dump() -> bytes:
    header = bytearray(32)
    header[:8] = b"UPRB\x01\x20\x10\x03"
    struct.pack_into("<5I", header, 8, 2, 15625, 156_250_000, 4, 1024)
    header[28:32] = b"PCPU"
    records = (
        struct.pack("<IHBB4H", 100, 0x000F, 0, 0, 10, 200, 180, 9),
        struct.pack("<IHBB4H", 15_725, 0x180F, 0, 0x61,
                    12, 250, 230, 11),
    )
    payload = b"".join(records)
    return (bytes(header) + payload + b"END!"
            + struct.pack("<I", binascii.crc32(payload) & 0xffffffff))


class UARTProbeHostTest(unittest.TestCase):
    def test_decode_and_text(self) -> None:
        metadata, records = uart_probe.parse_dump(make_dump())
        self.assertEqual(metadata["schema"], "ETH2")
        self.assertEqual(metadata["sequence"], 7)
        self.assertEqual(records[1]["net_clk"], 15725)
        report = uart_probe.render_text(metadata, records)
        self.assertIn("156.2500 MHz", report)
        self.assertIn("10G reference-derived clock GOOD", report)
        self.assertIn("QPLL lock                  GOOD", report)
        self.assertIn("PCS lane 0 block lock       GOOD", report)
        self.assertIn("PCS lane 1 block lock       GOOD", report)
        self.assertIn("RX error sticky flags       GOOD", report)

    def test_crc_rejected(self) -> None:
        data = bytearray(make_dump())
        data[40] ^= 1
        with self.assertRaisesRegex(ValueError, "CRC mismatch"):
            uart_probe.parse_dump(bytes(data))

    def test_standalone_diagnostic_schema(self) -> None:
        metadata, records = uart_probe.parse_dump(make_dump(b"ETHD"))
        report = uart_probe.render_text(metadata, records)
        self.assertIn("slave_tx_reset_done", report)
        self.assertIn("TX user clock / CDC         GOOD", report)
        self.assertIn("RX-valid and TX-ready activity", report)

    def test_stream_framing_keeps_read_ahead(self) -> None:
        expected = make_dump(b"ETHD")
        stream = bytearray(b"stale dump tail END!" + expected[:19])
        self.assertIsNone(uart_probe.pop_complete_frame(stream))
        stream.extend(expected[19:50])
        self.assertIsNone(uart_probe.pop_complete_frame(stream))
        stream.extend(expected[50:] + b"next frame read-ahead")
        self.assertEqual(uart_probe.pop_complete_frame(stream), expected)
        self.assertEqual(stream, b"next frame read-ahead")

    def test_stream_framing_rejects_false_magic(self) -> None:
        expected = make_dump()
        stream = bytearray(b"UPRB invalid header bytes" + expected)
        self.assertEqual(uart_probe.pop_complete_frame(stream), expected)

    def test_loopback_schema(self) -> None:
        metadata, records = uart_probe.parse_dump(make_loopback_dump())
        self.assertEqual(metadata["schema"], "PLBK")
        self.assertEqual(records[0]["destination_mac"], 0x554433221100)
        report = uart_probe.render_text(metadata, records)
        self.assertIn("00:11:22:33:44:55", report)
        self.assertIn("route port 0 -> 1", report)
        self.assertIn("packet RX observed        GOOD", report)
        self.assertIn("channel swap              GOOD", report)

    def test_cpu_processing_schema(self) -> None:
        metadata, records = uart_probe.parse_dump(make_cpu_dump())
        self.assertEqual(metadata["schema"], "PCPU")
        self.assertEqual(records[1]["tx_packets"], 11)
        report = uart_probe.render_text(metadata, records)
        self.assertIn("completed descriptors        2", report)
        self.assertIn("accepted RxRAM words         50", report)
        self.assertIn("completed TX packets         2", report)
        self.assertIn("CPU/DMA forwarding progress  GOOD", report)


if __name__ == "__main__":
    unittest.main()
