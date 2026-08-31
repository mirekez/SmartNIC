#!/usr/bin/env python3
"""Read KlusterLab SFP EEPROM/DDM through GPIO2/3 without a kernel I2C bus.

The board routes CM4 GPIO2/3 to a TCA9548A powered at 1.8 V.  Lines are
implemented strictly as open drain: output-low asserts a line and input mode
releases it.  The mux is returned to all-channels-disabled before exit.
"""

import argparse
import time

import RPi.GPIO as GPIO


SDA = 2
SCL = 3


class BitBangI2C:
    def __init__(self, delay_us: int = 20):
        self.delay = delay_us / 1_000_000.0
        GPIO.setwarnings(False)
        GPIO.setmode(GPIO.BCM)
        self.release(SDA)
        self.release(SCL)
        self.wait()

    def wait(self):
        time.sleep(self.delay)

    @staticmethod
    def low(pin):
        GPIO.setup(pin, GPIO.OUT, initial=GPIO.LOW)

    @staticmethod
    def release(pin):
        GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_OFF)

    def scl_high(self):
        self.release(SCL)
        deadline = time.monotonic() + 0.050
        while not GPIO.input(SCL):
            if time.monotonic() >= deadline:
                raise TimeoutError("SCL held low")
        self.wait()

    def start(self):
        self.release(SDA)
        self.scl_high()
        self.low(SDA)
        self.wait()
        self.low(SCL)
        self.wait()

    def stop(self):
        self.low(SDA)
        self.wait()
        self.scl_high()
        self.release(SDA)
        self.wait()

    def write_byte(self, value: int) -> bool:
        for bit in range(7, -1, -1):
            self.low(SCL)
            if value & (1 << bit):
                self.release(SDA)
            else:
                self.low(SDA)
            self.wait()
            self.scl_high()
        self.low(SCL)
        self.release(SDA)
        self.wait()
        self.scl_high()
        ack = not GPIO.input(SDA)
        self.low(SCL)
        self.wait()
        return ack

    def read_byte(self, acknowledge: bool) -> int:
        value = 0
        self.release(SDA)
        for _ in range(8):
            self.low(SCL)
            self.wait()
            self.scl_high()
            value = (value << 1) | int(GPIO.input(SDA))
        self.low(SCL)
        if acknowledge:
            self.low(SDA)
        else:
            self.release(SDA)
        self.wait()
        self.scl_high()
        self.low(SCL)
        self.release(SDA)
        self.wait()
        return value

    def probe(self, address: int) -> bool:
        self.start()
        ack = self.write_byte(address << 1)
        self.stop()
        return ack

    def write(self, address: int, data: bytes) -> bool:
        self.start()
        if not self.write_byte(address << 1):
            self.stop()
            return False
        for value in data:
            if not self.write_byte(value):
                self.stop()
                return False
        self.stop()
        return True

    def read_registers(self, address: int, offset: int, count: int) -> bytes:
        self.start()
        if not self.write_byte(address << 1) or not self.write_byte(offset):
            self.stop()
            raise OSError(f"no response from 0x{address:02x}")
        self.start()
        if not self.write_byte((address << 1) | 1):
            self.stop()
            raise OSError(f"no read response from 0x{address:02x}")
        data = bytes(self.read_byte(index + 1 < count) for index in range(count))
        self.stop()
        return data

    def cleanup(self):
        self.release(SDA)
        self.release(SCL)
        GPIO.cleanup((SDA, SCL))


def ascii_field(data: bytes) -> str:
    return data.decode("ascii", errors="replace").strip(" \x00")


def print_module(bus: BitBangI2C, channel: int):
    base = bus.read_registers(0x50, 0, 96)
    print(
        f"channel={channel} identifier=0x{base[0]:02x} "
        f"vendor={ascii_field(base[20:36])!r} "
        f"part={ascii_field(base[40:56])!r} "
        f"serial={ascii_field(base[68:84])!r} "
        f"diagnostics={'yes' if base[92] & 0x40 else 'no'}"
    )
    if not bus.probe(0x51):
        print("  DDM address 0x51 absent")
        return
    ddm = bus.read_registers(0x51, 96, 16)
    temperature_raw = int.from_bytes(ddm[0:2], "big", signed=True)
    voltage_raw = int.from_bytes(ddm[2:4], "big")
    tx_bias_raw = int.from_bytes(ddm[4:6], "big")
    tx_power_raw = int.from_bytes(ddm[6:8], "big")
    rx_power_raw = int.from_bytes(ddm[8:10], "big")
    status = ddm[14]
    print(
        f"  temperature={temperature_raw / 256:.2f} C "
        f"voltage={voltage_raw / 10000:.4f} V "
        f"tx_bias={tx_bias_raw * 0.002:.3f} mA "
        f"tx_power={tx_power_raw * 0.0001:.4f} mW "
        f"rx_power={rx_power_raw * 0.0001:.4f} mW"
    )
    print(
        f"  status=0x{status:02x} tx_disable={int(bool(status & 0x40))} "
        f"tx_fault={int(bool(status & 0x04))} rx_los={int(bool(status & 0x02))}"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--delay-us", type=int, default=20)
    args = parser.parse_args()
    bus = BitBangI2C(args.delay_us)
    mux = None
    try:
        addresses = [address for address in range(0x70, 0x78) if bus.probe(address)]
        if len(addresses) != 1:
            raise RuntimeError(f"expected one TCA9548A at 0x70..0x77, found {addresses}")
        mux = addresses[0]
        print(f"mux=0x{mux:02x}")
        for channel in range(8):
            if not bus.write(mux, bytes((1 << channel,))):
                raise OSError("mux selection failed")
            time.sleep(0.002)
            if bus.probe(0x50):
                print_module(bus, channel)
    finally:
        if mux is not None:
            bus.write(mux, b"\x00")
        bus.cleanup()


if __name__ == "__main__":
    main()
