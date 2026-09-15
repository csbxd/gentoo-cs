# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="TinyGo compiler for embedded systems and WebAssembly (Linux ARM64)"
HOMEPAGE="https://tinygo.org/ https://github.com/tinygo-org/tinygo"
SRC_URI="https://github.com/tinygo-org/tinygo/releases/download/v${PV}/tinygo${PV}.linux-arm64.tar.gz"

S="${WORKDIR}/tinygo"

LICENSE="BSD Apache-2.0-with-LLVM-exceptions MIT"
SLOT="0"
KEYWORDS="-* ~arm64"
REQUIRED_USE="elibc_glibc"
RESTRICT="strip"

RDEPEND="
	>=dev-lang/go-1.24
	<dev-lang/go-1.28
	sys-devel/gcc
"

QA_PREBUILT="*"

src_configure() { :; }
src_compile() { :; }

src_install() {
	dodir /opt/tinygo
	cp -a . "${ED}/opt/tinygo/" || die "Failed to install TinyGo distribution"
	dosym -r /opt/tinygo/bin/tinygo /usr/bin/tinygo
}
