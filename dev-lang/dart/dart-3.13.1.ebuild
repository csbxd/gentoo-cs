# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker

DESCRIPTION="The Dart SDK (official prebuilt binary for Linux ARM64)"
HOMEPAGE="https://dart.dev https://github.com/dart-lang/sdk"
SRC_URI="
	https://storage.googleapis.com/dart-archive/channels/stable/release/${PV}/sdk/dartsdk-linux-arm64-release.zip
		-> ${P}-arm64.zip
"

# The archive extracts into a top-level dart-sdk/ directory.
S="${WORKDIR}/dart-sdk"

LICENSE="BSD"
SLOT="0"
KEYWORDS="-* ~arm64"
RESTRICT="strip"

QA_PREBUILT="*"
BDEPEND="app-arch/unzip"

src_install() {
	# Preserve executable bits from the official SDK archive.
	dodir /usr/lib/dart
	cp -r . "${ED}/usr/lib/dart/" || die

	# Defensively guarantee the launchers and utilities are executable.
	fperms +x /usr/lib/dart/bin/dart
	fperms +x /usr/lib/dart/bin/dartaotruntime
	fperms +x /usr/lib/dart/bin/utils/gen_snapshot
	if [[ -e "${ED}/usr/lib/dart/bin/utils/wasm-opt" ]]; then
		fperms +x /usr/lib/dart/bin/utils/wasm-opt
	fi

	dosym ../lib/dart/bin/dart /usr/bin/dart
	dosym ../lib/dart/bin/dartaotruntime /usr/bin/dartaotruntime
}
