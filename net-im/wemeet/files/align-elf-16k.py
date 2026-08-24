#!/usr/bin/env python3
"""Repack an ELF64 file so PT_LOAD offsets are congruent on 16 KiB pages."""

import struct
import sys
from pathlib import Path


ELF_HEADER = struct.Struct("<16sHHIQQQIHHHHHH")
PROGRAM_HEADER = struct.Struct("<IIQQQQQQ")
SECTION_HEADER = struct.Struct("<IIQQQQIIQQ")
PT_LOAD = 1
PAGE_SIZE = 16384


def shifted(offset: int, insertions: list[tuple[int, int]]) -> int:
    if offset == 0:
        return 0
    return offset + sum(size for point, size in insertions if point <= offset)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} INPUT OUTPUT")

    source_path, output_path = map(Path, sys.argv[1:3])
    source = bytearray(source_path.read_bytes())
    header = list(ELF_HEADER.unpack_from(source))
    ident = header[0]
    if ident[:6] != b"\x7fELF\x02\x01":
        raise SystemExit("expected ELF64 little-endian input")

    phoff, shoff = header[5], header[6]
    phentsize, phnum = header[9], header[10]
    shentsize, shnum = header[11], header[12]
    if phentsize != PROGRAM_HEADER.size or shentsize != SECTION_HEADER.size:
        raise SystemExit("unexpected ELF table entry size")

    phdrs = [
        list(PROGRAM_HEADER.unpack_from(source, phoff + i * phentsize))
        for i in range(phnum)
    ]
    shdrs = [
        list(SECTION_HEADER.unpack_from(source, shoff + i * shentsize))
        for i in range(shnum)
    ]

    insertions: list[tuple[int, int]] = []
    accumulated = 0
    for phdr in sorted(
        (item for item in phdrs if item[0] == PT_LOAD and item[5]),
        key=lambda item: item[2],
    ):
        original_offset, virtual_address = phdr[2], phdr[3]
        padding = (
            virtual_address - original_offset - accumulated
        ) % PAGE_SIZE
        if padding:
            insertions.append((original_offset, padding))
            accumulated += padding

    output = bytearray()
    cursor = 0
    for point, padding in insertions:
        output.extend(source[cursor:point])
        output.extend(b"\0" * padding)
        cursor = point
    output.extend(source[cursor:])

    new_shoff = shifted(shoff, insertions)
    header[6] = new_shoff
    ELF_HEADER.pack_into(output, 0, *header)

    for index, phdr in enumerate(phdrs):
        phdr[2] = shifted(phdr[2], insertions)
        if phdr[0] == PT_LOAD:
            phdr[7] = max(phdr[7], PAGE_SIZE)
        PROGRAM_HEADER.pack_into(output, phoff + index * phentsize, *phdr)

    for index, shdr in enumerate(shdrs):
        shdr[4] = shifted(shdr[4], insertions)
        SECTION_HEADER.pack_into(output, new_shoff + index * shentsize, *shdr)

    output_path.write_bytes(output)
    output_path.chmod(source_path.stat().st_mode)
    print(f"insertions={insertions}; size={len(source)}->{len(output)}")


if __name__ == "__main__":
    main()
