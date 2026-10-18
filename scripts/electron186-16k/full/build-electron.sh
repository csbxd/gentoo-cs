#!/usr/bin/env bash
set -euo pipefail
cd /build
mode="${1:-build}"
if [[ "$mode" == configure || "$mode" == precompile ]]; then
  python stage-libcc-for-electron.py --prepare-only
else
  test -f /build/.full-libcc-build-complete
  python stage-libcc-for-electron.py
fi
cd /build/electron-1.8.6
export CC=gcc CXX=g++ AR=ar
export CC_host=gcc CXX_host=g++ AR_host=ar
python - <<'PY'
import sys
sys.path.insert(0, 'script')
import update
sys.argv = ['update.py', '--defines', 'clang=0 sysroot=/ pkg-config=pkg-config']
sys.exit(update.run_gyp('arm64', 0))
PY
if [[ "$mode" == configure ]]; then
  exit 0
fi
if [[ "$mode" == precompile ]]; then
  python - <<'PY'
import re
import subprocess
import sys
graph = subprocess.check_output(['ninja', '-C', 'out/R', '-t', 'graph', 'electron'])
objects = re.findall(r'\[label="([^"]+\.o)"\]', graph)
# The main executable object has a blanket dependency on final runtime copies.
objects = [obj for obj in objects if obj != 'obj/atom/app/electron.atom_main.o']
print('Precompiling %d reachable Electron object files without final links' % len(objects))
sys.exit(subprocess.call(['ninja', '-C', 'out/R', '-j2', 'resources/electron.asar',
                          'resources/default_app.asar'] + objects))
PY
  exit 0
fi
ninja -C out/R -j"${ELECTRON_JOBS:-6}" electron
test -x out/R/electron
test -f out/R/libnode.so
python /build/assemble-electron-runtime.py
ELECTRON_RUN_AS_NODE=1 /build/electron186-runtime/electron \
  -e 'console.log(JSON.stringify(process.versions))' \
  | tee /build/electron186-runtime/versions.json
(
  cd /build/electron186-runtime
  sha256sum electron libnode.so libffmpeg.so snapshot_blob.bin > SHA256SUMS
)
touch /build/.full-electron-build-complete
