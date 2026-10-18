#!/usr/bin/env python3
"""Fetch only V8/ICU and generator dependencies locked by Electron 1.8.6."""
from pathlib import Path
import base64
import hashlib
import json
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent
LOCK = json.loads((ROOT / "source-lock.json").read_text())
DOWNLOADS = ROOT / "downloads"
DOWNLOADS.mkdir(exist_ok=True)

ARCHIVES = [
    ("v8-correct", f"https://codeload.github.com/v8/v8/tar.gz/{LOCK['v8']}", "v8", True),
    ("libcc", f"https://codeload.github.com/electron/libchromiumcontent/tar.gz/{LOCK['libchromiumcontent']}", "libcc", True),
    ("gyp", f"https://chromium.googlesource.com/external/gyp/+archive/{LOCK['gyp']}.tar.gz", "v8/tools/gyp", False),
    ("common", f"https://chromium.googlesource.com/chromium/src/base/trace_event/common/+archive/{LOCK['trace_event_common']}.tar.gz", "v8/base/trace_event/common", False),
    ("icu", f"https://chromium.googlesource.com/chromium/deps/icu/+archive/{LOCK['icu']}.tar.gz", "v8/third_party/icu", False),
    ("jinja2", f"https://chromium.googlesource.com/chromium/src/third_party/jinja2/+archive/{LOCK['jinja2']}.tar.gz", "v8/third_party/jinja2", False),
    ("markupsafe", f"https://chromium.googlesource.com/chromium/src/third_party/markupsafe/+archive/{LOCK['markupsafe']}.tar.gz", "v8/third_party/markupsafe", False),
]

if (ROOT / "v8").exists():
    raise SystemExit("v8/ already exists; use a fresh directory to prepare sources")

for name, url, destination, strip_root in ARCHIVES:
    archive = DOWNLOADS / f"{name}.tar.gz"
    if not archive.exists():
        print(f"Downloading {name}", flush=True)
        urllib.request.urlretrieve(url, archive)
    expected = LOCK["archive_sha256"][archive.name]
    actual = hashlib.sha256(archive.read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(f"SHA256 mismatch for {archive}")
    target = ROOT / destination
    target.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as source:
        for member in source:
            if strip_root:
                member.name = "/".join(member.name.split("/")[1:])
            if member.name:
                source.extract(member, target, filter="data")

header = ROOT / "v8/testing/gtest/include/gtest/gtest_prod.h"
header.parent.mkdir(parents=True, exist_ok=True)
header_url = f"https://chromium.googlesource.com/external/github.com/google/googletest/+/{LOCK['gtest_prod_header']}/googletest/include/gtest/gtest_prod.h?format=TEXT"
header.write_bytes(base64.b64decode(urllib.request.urlopen(header_url).read()))

for patch in sorted((ROOT / "libcc/patches/v8").glob("*.patch")):
    subprocess.run(["patch", "-p1", "--batch", "-i", str(patch)], cwd=ROOT / "v8", check=True)
for patch in sorted((ROOT / "libcc/patches/third_party/icu").glob("*.patch")):
    subprocess.run(["patch", "-p1", "--batch", "-i", str(patch)], cwd=ROOT / "v8/third_party/icu", check=True)
subprocess.run(["patch", "-p1", "--batch", "-i", str(ROOT / "gcc16-compat.patch")], cwd=ROOT / "v8", check=True)
print("Sources ready; run build-mksnapshot.sh with Python 2.7 on PATH")
