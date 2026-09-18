# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

LLVM_COMPAT=( 22 )
EGIT_REPO_URI="https://github.com/xgo-dev/llgo.git"
EGIT_BRANCH="main"

inherit git-r3 go-module llvm-r2

DESCRIPTION="Go compiler based on LLVM with direct C interoperability"
HOMEPAGE="https://github.com/xgo-dev/llgo"

LICENSE="Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD MIT"
SLOT="0"
KEYWORDS=""
IUSE="lldb"
# The full upstream suite requires cross toolchains, emulators and extra libraries.
RESTRICT="test"

DEPEND="$(llvm_gen_dep 'llvm-core/llvm:${LLVM_SLOT}=')"
RDEPEND="
	${DEPEND}
	>=dev-lang/go-1.27.0
	<dev-lang/go-1.28
	>=dev-libs/boehm-gc-8[threads]
	dev-libs/libffi
	>=dev-libs/openssl-3
	sys-libs/libunwind
	virtual/pkgconfig
	virtual/zlib
	$(llvm_gen_dep '
		llvm-core/clang:${LLVM_SLOT}
		llvm-core/lld:${LLVM_SLOT}
		lldb? ( llvm-core/lldb )
	')
"
BDEPEND=">=dev-lang/go-1.27.0"

DOCS=( README.md THIRD_PARTY_NOTICES.md )

src_unpack() {
	export GOTOOLCHAIN=local
	git-r3_src_unpack
	go-module_live_vendor
}

src_configure() {
	go-module_src_configure
	export CGO_ENABLED=1 GOTOOLCHAIN=local GOPROXY=off

	local llvm_cppflags llvm_ldflags
	llvm_cppflags=$(llvm-config --cppflags) || die
	llvm_ldflags=$(llvm-config --ldflags --libs --system-libs) || die
	export CGO_CPPFLAGS="${CGO_CPPFLAGS} ${llvm_cppflags}"
	export CGO_CXXFLAGS="${CGO_CXXFLAGS} -std=c++17"
	export CGO_LDFLAGS="${CGO_LDFLAGS} ${llvm_ldflags}"
}

src_compile() {
	ego build -mod=vendor -trimpath -buildvcs=true -tags=byollvm \
		-ldflags "-X github.com/xgo-dev/llgo/internal/env.buildVersion=9999-${EGIT_VERSION:0:12}" \
		-o bin/llgo ./cmd/llgo
}

src_install() {
	local dest="/usr/$(get_libdir)/llgo"
	insinto "${dest}"
	doins -r runtime targets
	exeinto "${dest}/bin"
	doexe bin/llgo

	# LLGo discovers runtime/ relative to its executable. Select the matching
	# system LLVM even when another slot is the user's default toolchain.
	cat > "${T}/llgo" <<-EOF || die
		#!/bin/sh
		export LLVM_CONFIG="${EPREFIX}/usr/lib/llvm/${LLVM_SLOT}/bin/llvm-config"
		export PATH="${EPREFIX}/usr/lib/llvm/${LLVM_SLOT}/bin:\${PATH}"
		exec "${EPREFIX}${dest}/bin/llgo" "\$@"
	EOF
	newbin "${T}/llgo" llgo
	einstalldocs
	dodoc -r LICENSES
}
