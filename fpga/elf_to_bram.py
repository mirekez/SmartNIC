#!/usr/bin/env python3
"""Convert ELF32 little-endian PT_LOAD segments into readmemh words."""

import argparse
import struct
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("elf", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--size", type=int, required=True)
    parser.add_argument("--word-bytes", type=int, default=32)
    return parser.parse_args()


def main():
    args = parse_args()
    blob = args.elf.read_bytes()
    if len(blob) < 52 or blob[:7] != b"\x7fELF\x01\x01\x01":
        raise SystemExit(f"{args.elf}: expected little-endian ELF32")

    header = struct.unpack_from("<16sHHIIIIIHHHHHH", blob)
    machine, entry, phoff = header[2], header[4], header[5]
    phentsize, phnum = header[9], header[10]
    if machine != 243:
        raise SystemExit(f"{args.elf}: expected RISC-V machine 243, got {machine}")
    if entry != 0:
        raise SystemExit(f"{args.elf}: reset entry must be zero, got 0x{entry:x}")
    if args.size <= 0 or args.word_bytes <= 0 or args.size % args.word_bytes:
        raise SystemExit("image size must be a positive multiple of word size")
    if phentsize < 32 or phoff + phentsize * phnum > len(blob):
        raise SystemExit(f"{args.elf}: invalid program-header table")

    image = bytearray(args.size)
    loaded = 0
    occupied = bytearray(args.size)
    for index in range(phnum):
        values = struct.unpack_from("<IIIIIIII", blob, phoff + index * phentsize)
        p_type, offset, vaddr, paddr, filesz, memsz, _, _ = values
        if p_type != 1:
            continue
        address = paddr if paddr else vaddr
        if filesz > memsz or offset + filesz > len(blob):
            raise SystemExit(f"{args.elf}: invalid PT_LOAD segment {index}")
        if address + memsz > args.size:
            raise SystemExit(
                f"{args.elf}: segment {index} end 0x{address + memsz:x} "
                f"exceeds {args.size}-byte BRAM")
        if any(occupied[address:address + memsz]):
            raise SystemExit(f"{args.elf}: overlapping PT_LOAD segment {index}")
        image[address:address + filesz] = blob[offset:offset + filesz]
        occupied[address:address + memsz] = b"\x01" * memsz
        loaded += memsz
    if not loaded or not occupied[0]:
        raise SystemExit(f"{args.elf}: no loadable reset image at address zero")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii") as output:
        for offset in range(0, args.size, args.word_bytes):
            # readmemh writes the right-most byte to memory bits [7:0].
            output.write(image[offset:offset + args.word_bytes][::-1].hex() + "\n")
    print(
        f"ELF_BRAM_IMAGE={args.output} bytes={args.size} "
        f"loaded={loaded} words={args.size // args.word_bytes}")


if __name__ == "__main__":
    main()
