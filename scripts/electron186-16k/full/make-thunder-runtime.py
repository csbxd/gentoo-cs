#!/usr/bin/env python3
"""Combine the rebuilt Electron with the user's installed Xunlei app files."""
import argparse
from pathlib import Path
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('electron', type=Path)
parser.add_argument('destination', type=Path)
parser.add_argument('--installed-thunder', type=Path, default=Path('/opt/xunlei-download'))
args = parser.parse_args()
if args.destination.exists():
    raise SystemExit('Destination already exists: ' + str(args.destination))
shutil.copytree(args.electron, args.destination, symlinks=False)
for relative in ('resources/app', 'resources/bin'):
    target = args.destination / relative
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(args.installed_thunder / relative, target)
for filename in ('libxl_stat.so', 'libxl_thunder_sdk.so', 'libgconf-2.so.4',
                 'download-complete.wav'):
    source = args.installed_thunder / filename
    if source.exists():
        shutil.copy2(source, args.destination / filename)
binary = args.destination / 'electron'
if binary.exists():
    binary.rename(args.destination / 'thunder')
launcher = args.destination / 'run-thunder.sh'
launcher.write_text('''#!/usr/bin/env bash
set -euo pipefail
runtime_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
export LD_LIBRARY_PATH="$runtime_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# The legacy app writes BHO/config.ini without creating its parent directory.
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$data_dir/ThunderNetwork/profiles/Thunder/BHO"
exec "$runtime_dir/thunder" "$@"
''')
launcher.chmod(0o755)
print(args.destination.resolve())
