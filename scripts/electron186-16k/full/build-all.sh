#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$task_root"
python3 sync-sources.py
podman build -f Containerfile -t localhost/electron186-16k-build .
podman build -f Containerfile.compat -t localhost/electron186-16k-build-compat .
podman run --rm -v "$task_root:/build" localhost/electron186-16k-build-compat \
  bash /build/full-build.sh 2>&1 | tee full-build.log
touch .full-libcc-build-complete
podman run --rm -v "$task_root:/build" localhost/electron186-16k-build-compat \
  bash /build/build-electron.sh build 2>&1 | tee electron-full-build.log
python3 verify-runtime.py electron186-runtime --json elf-layout.json
