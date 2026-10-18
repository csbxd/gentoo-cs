#!/usr/bin/env bash
set -euo pipefail
cd /build/chromium-59.0.3071.115
test -f .electron186-16k-patched
rm -f /build/.full-libcc-build-complete
export CC=gcc CXX=g++
getconf PAGESIZE
gcc --version | head -1
if [[ ! -x out/Release/gn ]]; then
  python tools/gn/bootstrap/bootstrap.py -s --no-clean
fi
gn=out/Release/gn
out_dir=out/electron186-16k
gn_args='import("//chromiumcontent/args/static_library.gn") target_cpu="arm64" is_debug=false is_official_build=false is_clang=false use_sysroot=false use_gold=false use_lld=false treat_warnings_as_errors=false fatal_linker_warnings=false symbol_level=0 v8_os_page_size="16" use_gtk3=false'
# Do not erase a completed object list when resuming the second pass. The
# upstream build assumes GN setup happens once; this combined script is resumable.
if [[ -s "$out_dir/obj/chromiumcontent/objects.gni" && -f "$out_dir/obj/chromiumcontent/build_libs.done" ]]; then
  CHROMIUMCONTENT_2ND_PASS=1 "$gn" gen "$out_dir" --args="$gn_args"
else
  rm -f "$out_dir/obj/chromiumcontent/build_libs.done"
  "$gn" gen "$out_dir" --args="$gn_args"
fi
ninja -C "$out_dir" -j8 chromiumcontent:chromiumcontent
CHROMIUMCONTENT_2ND_PASS=1 ninja -C "$out_dir" -j4 chromiumcontent:libs
date -u +%Y-%m-%dT%H:%M:%SZ > /build/.full-libcc-build-complete
