# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

LLVM_COMPAT=( 22 )

inherit go-module llvm-r2

DESCRIPTION="Go compiler based on LLVM with direct C interoperability"
HOMEPAGE="https://github.com/xgo-dev/llgo"
SRC_URI="https://github.com/xgo-dev/llgo/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

# Fetch the pinned modules through Portage so builds need neither network
# access nor a separately hosted vendor archive. Keep in sync with go.mod.
LLGO_MODULES=(
	github.com/creack/goselect@v0.1.2
	github.com/davecgh/go-spew@v1.1.1
	github.com/google/go-cmp@v0.6.0
	github.com/goplus/cobra@v1.9.12
	github.com/goplus/gogen@v1.23.5
	github.com/goplus/lib@v0.5.2
	github.com/goplus/mod@v0.22.0
	github.com/mattn/go-isatty@v0.0.20
	github.com/mattn/go-colorable@v0.1.13
	github.com/mattn/go-runewidth@v0.0.16
	github.com/mattn/go-tty@v0.0.8
	github.com/qiniu/x@v1.18.3
	github.com/pmezard/go-difflib@v1.0.0
	github.com/rivo/uniseg@v0.4.7
	github.com/xgo-dev/llvm@v0.10.0
	github.com/xgo-dev/plan9asm@v0.5.2
	github.com/stretchr/testify@v1.8.4
	github.com/yuin/goldmark@v1.4.13
	go.bug.st/serial@v1.6.4
	go.yaml.in/yaml/v3@v3.0.5
	golang.org/x/mod@v0.40.0
	golang.org/x/net@v0.58.0
	golang.org/x/sync@v0.22.0
	golang.org/x/sys@v0.6.0
	golang.org/x/sys@v0.47.0
	golang.org/x/tools@v0.49.0
	golang.org/x/telemetry@v0.0.0-20260811182544-a038080d80e5
	gopkg.in/yaml.v3@v3.0.1
)
for module in "${LLGO_MODULES[@]}"; do
	module_path=${module%@*}
	module_version=${module##*@}
	for extension in info mod zip; do
		SRC_URI+=" mirror://goproxy/${module_path}/@v/${module_version}.${extension}
			-> ${module_path//\//%2F}%2F@v%2F${module_version}.${extension}"
	done
done
unset module module_path module_version extension

LICENSE="Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
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
	unpack "${P}.tar.gz"

	local module module_path module_version extension proxy_dir
	for module in "${LLGO_MODULES[@]}"; do
		module_path=${module%@*}
		module_version=${module##*@}
		proxy_dir="${WORKDIR}/go-proxy/${module_path}/@v"
		mkdir -p "${proxy_dir}" || die
		for extension in info mod zip; do
			ln -s "${DISTDIR}/${module_path//\//%2F}%2F@v%2F${module_version}.${extension}" \
				"${proxy_dir}/${module_version}.${extension}" || die
		done
	done

	export GOPROXY="file://${WORKDIR}/go-proxy" GOSUMDB=off GOTOOLCHAIN=local
	cd "${S}" || die
	ego mod download
	ego mod verify
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
	ego build -mod=readonly -trimpath -tags=byollvm \
		-ldflags "-X github.com/xgo-dev/llgo/internal/env.buildVersion=v${PV}" \
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
