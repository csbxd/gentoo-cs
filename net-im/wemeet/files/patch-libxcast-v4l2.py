#!/usr/bin/env python3
"""Fix Wemeet's incomplete ARM64 V4L2 capture support.

Wemeet clears the buffer passed to VIDIOC_DQBUF and restores ``type`` but not
``memory``.  v4l2loopback rejects memory=0 with EINVAL.  Reuse two existing
instructions to set V4L2_MEMORY_MMAP without changing the ELF layout.

The capture worker also accepts only MJPG and YUYV.  Add an NV12 branch whose
call placeholder is redirected by libwemeet-camera-compat at load time.
"""

import hashlib
import sys
from pathlib import Path


EXPECTED_SHA256 = "6268b4dde3e9f3ada86f4f051126d61ce234054a498ce90178d1284423c5e990"
PATCHES = (
    (
        0x27279C,
        bytes.fromhex(
            "e1 23 02 91 e0 03 08 aa e9 06 00 94 00 03 40 f9 "
            "39 d3 02 94 08 07 40 f9 e0 57 00 d0 e4 57 00 d0 "
            "e1 36 80 52 06 59 40 b9 e2 03 1f 32 e3 03 00 32 "
            "00 58 00 91 84 18 1a 91 e5 03 18 aa af 05 03 94 "
            "f8 7b 1e 32 12 00 00 14"
        ),
        bytes.fromhex(
            "2a 46 a6 52 ca c9 8a 72 3f 01 0a 6b 41 01 00 54 "
            "e0 03 19 2a e1 03 1a 2a e2 03 1b aa 03 69 40 b9 "
            "e0 03 1f aa fb 03 00 aa 00 01 00 b4 d1 ff ff 17 "
            "1f 20 03 d5 f8 7b 1e 32 15 00 00 14 1f 20 03 d5 "
            "1f 20 03 d5 1f 20 03 d5"
        ),
    ),
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
    print("patched libxcast.so for V4L2 MMAP and NV12 capture")


if __name__ == "__main__":
    main()
