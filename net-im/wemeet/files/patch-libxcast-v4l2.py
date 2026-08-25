#!/usr/bin/env python3
"""Fix Wemeet's incomplete v4l2_buffer setup on ARM64.

Wemeet clears the buffer passed to VIDIOC_DQBUF and restores ``type`` but not
``memory``.  v4l2loopback rejects memory=0 with EINVAL.  Reuse two existing
instructions to set V4L2_MEMORY_MMAP without changing the ELF layout.
"""

import hashlib
import sys
from pathlib import Path


EXPECTED_SHA256 = "6268b4dde3e9f3ada86f4f051126d61ce234054a498ce90178d1284423c5e990"
PATCHES = (
    # ldr w21, [x19, #0x40] -> str w8, [x20, #0x3c]
    (0x2742BC, bytes.fromhex("75 42 40 b9"), bytes.fromhex("88 3e 00 b9")),
    # mov w0, w21 -> ldr w0, [x19, #0x40]
    (0x2742C8, bytes.fromhex("e0 03 15 2a"), bytes.fromhex("60 42 40 b9")),
)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} INPUT OUTPUT")

    source_path, output_path = map(Path, sys.argv[1:3])
    source = source_path.read_bytes()
    digest = hashlib.sha256(source).hexdigest()
    if digest != EXPECTED_SHA256:
        raise SystemExit(
            f"unexpected libxcast.so SHA256: {digest}; expected {EXPECTED_SHA256}"
        )

    output = bytearray(source)
    for offset, before, after in PATCHES:
        actual = output[offset : offset + len(before)]
        if actual != before:
            raise SystemExit(
                f"unexpected instruction at 0x{offset:x}: {actual.hex()}"
            )
        output[offset : offset + len(before)] = after

    output_path.write_bytes(output)
    output_path.chmod(source_path.stat().st_mode)
    print("patched libxcast.so to set V4L2_MEMORY_MMAP before VIDIOC_DQBUF")


if __name__ == "__main__":
    main()
