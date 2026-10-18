#!/usr/bin/env bash
set -euo pipefail
task_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
python2_bin="${PYTHON2_BIN:-$(command -v python2.7 || true)}"
if [[ -z "$python2_bin" || ! -x "$python2_bin" ]]; then
  echo 'Python 2.7 is required; set PYTHON2_BIN to its executable.' >&2
  exit 1
fi
python2_bin="$(readlink -f -- "$python2_bin")"
mkdir -p "$task_dir/.python2-bin"
ln -sfn "$python2_bin" "$task_dir/.python2-bin/python"
export PATH="$task_dir/.python2-bin:$PATH"
cd "$task_dir/v8"
export PYTHONPATH="gypfiles:tools/gyp/pylib${PYTHONPATH:+:$PYTHONPATH}"
export GYP_GENERATORS=make
"$python2_bin" tools/gyp/gyp --generator-output=out src/v8.gyp \
  -Igypfiles/standalone.gypi --depth=. \
  -Dv8_target_arch=arm64 -Dtarget_arch=arm64 -Dhost_arch=arm64 \
  -Dclang=0 -Dhost_clang=0 \
  -Dv8_enable_i18n_support=1 -Dv8_enable_inspector=0 \
  -Dv8_promise_internal_field_count=1 \
  -Dlinux_use_bundled_binutils=0 -Dlinux_use_bundled_gold=0 \
  -Dwerror= -Dv8_use_external_startup_data=0 -Dv8_os_page_size=16
make -C out BUILDTYPE=Release "builddir=$task_dir/v8/out/out/Release" \
  -j"${JOBS:-8}" mksnapshot
cd "$task_dir/v8/out/out/Release"
./mksnapshot --random-seed=314159265 --v8_os_page_size=16 \
  --startup_blob="$task_dir/snapshot_blob-16k.bin"
