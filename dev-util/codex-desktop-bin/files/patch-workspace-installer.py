#!/usr/bin/env python3
# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

"""Keep the application's installer, with a packaged Linux ARM64 fallback."""

import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import sys


def inject(source, marker, make_code):
    location = source.index(marker)
    start = source.rfind("async function ", 0, location)
    function = re.match(r"async function [\w$]+\(([^)]*)\)\{", source[start:])
    if function is None:
        raise ValueError(f"Upstream installer changed near {marker}")
    parameters = [part.split("=", 1)[0] for part in function[1].split(",")]
    position = start + function.end()
    return source[:position] + make_code(parameters) + source[position:]


def patch(source):
    def manifest(parameters):
        url, signal = parameters[:2]
        return (
            f"if(process.platform===`linux`&&process.arch===`arm64`&&{url}==="
            "`https://persistent.oaistatic.com/codex-primary-runtime/latest/linux-arm64/LATEST.json`){"
            f"{signal}?.throwIfAborted();return JSON.parse(await require(`node:fs/promises`).readFile("
            "require(`node:path`).join(process.resourcesPath,`gentoo-workspace`,`manifest.json`),`utf8`));}"
        )

    def archive(parameters):
        url, destination, progress, signal = parameters[:4]
        return (
            f"if({url}===require(`node:url`).pathToFileURL(require(`node:path`).join("
            "process.resourcesPath,`gentoo-workspace`,`gentoo-arm64-workspace.tar.xz`)).href){"
            f"{signal}?.throwIfAborted();await require(`node:fs/promises`).copyFile("
            f"require(`node:url`).fileURLToPath({url}),{destination});{signal}?.throwIfAborted();"
            f"let gentooSize=(await require(`node:fs/promises`).stat({destination})).size;"
            f"{progress}?.({{downloadedBytes:gentooSize,totalBytes:gentooSize}});return;}}"
        )

    source = inject(source, "Failed to download primary runtime manifest", manifest)
    return inject(source, "Failed to download primary runtime archive", archive)


def entries(tree, prefix=""):
    for name, entry in tree.get("files", {}).items():
        path = prefix + "/" + name
        if "files" in entry:
            yield from entries(entry, path)
        elif "offset" in entry and not entry.get("unpacked"):
            yield path, entry


def main(path):
    temporary = path.with_suffix(".asar.gentoo")
    try:
        with path.open("rb") as stream:
            prefix = struct.unpack("<4I", stream.read(16))
            if prefix[0] != 4:
                raise ValueError("Unsupported ASAR header")
            header = json.loads(stream.read(prefix[3]))
            start = 8 + prefix[1]
            files = sorted(entries(header), key=lambda item: int(item[1]["offset"]))
            replacements = {}
            for name, entry in files:
                if not name.startswith("/.vite/build/") or not name.endswith(".js"):
                    continue
                stream.seek(start + int(entry["offset"]))
                content = stream.read(entry["size"])
                if b"Failed to download primary runtime manifest" in content:
                    if b"gentoo-workspace" in content:
                        raise ValueError("ASAR already contains the Gentoo workspace patch")
                    replacements[name] = patch(content.decode()).encode()
            if len(replacements) != 1:
                raise ValueError("Expected exactly one upstream workspace installer module")
            original = {}
            offset = 0
            for name, entry in files:
                original[name] = (int(entry["offset"]), entry["size"])
                content = replacements.get(name)
                if content is not None:
                    entry["size"] = len(content)
                    integrity = entry.get("integrity")
                    if integrity is not None:
                        if integrity["algorithm"] != "SHA256":
                            raise ValueError("Unsupported ASAR integrity algorithm")
                        block = integrity["blockSize"]
                        integrity["hash"] = hashlib.sha256(content).hexdigest()
                        integrity["blocks"] = [hashlib.sha256(content[i:i + block]).hexdigest()
                                               for i in range(0, len(content), block)]
                entry["offset"] = str(offset)
                offset += entry["size"]
            encoded = json.dumps(header, ensure_ascii=False, separators=(",", ":")).encode()
            padded = encoded + b"\0" * (-len(encoded) % 4)
            with temporary.open("wb") as output:
                output.write(struct.pack("<4I", 4, len(padded) + 8, len(padded) + 4, len(encoded)))
                output.write(padded)
                for name, entry in files:
                    if name in replacements:
                        output.write(replacements[name])
                        continue
                    original_offset, size = original[name]
                    stream.seek(start + original_offset)
                    while size:
                        chunk = stream.read(min(size, 1024 * 1024))
                        if not chunk:
                            raise ValueError("Truncated ASAR payload")
                        output.write(chunk)
                        size -= len(chunk)
        shutil.copymode(path, temporary)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    print("Patched workspace installer to use the packaged ARM64 fallback")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
