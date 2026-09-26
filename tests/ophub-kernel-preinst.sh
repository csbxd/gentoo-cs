#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Exercise the actual ebuild's collision guard without using the live root.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export EAPI=8 PV=6.18.53_p20260922 WORKDIR=$scratch/work
inherit() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
source "$repo/sys-kernel/ophub-kernel-bin/ophub-kernel-bin-${PV}.ebuild"
EROOT=$scratch/root
ED=$scratch/image
mkdir -p "$EROOT/lib/modules/$KV_FULL/kernel" "$ED/lib/modules/$KV_FULL/kernel"
printf '%s\n' 'original module bytes' > "$ED/lib/modules/$KV_FULL/kernel/test.ko"
# Missing manual tree/file is a normal first installation.
(pkg_preinst)
cp "$ED/lib/modules/$KV_FULL/kernel/test.ko" "$EROOT/lib/modules/$KV_FULL/kernel/test.ko"
# Byte-identical adoption is allowed.
(pkg_preinst)
printf '%s\n' 'different ABI under the same release' > "$EROOT/lib/modules/$KV_FULL/kernel/test.ko"
if (pkg_preinst) 2>"$scratch/expected-error"; then
	printf '%s\n' 'ERROR: same-release mismatch was accepted' >&2
	exit 1
fi
grep -q 'Different existing kernel/test.ko' "$scratch/expected-error"
printf '%s\n' 'preinst: first install, identical adoption and mismatch refusal passed'
