# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

LLVM_COMPAT=( 22 )
COMPILER_RT_VERSION=22.1.8
EGIT_REPO_URI="https://github.com/tinygo-org/tinygo.git"
EGIT_BRANCH="dev"
EGIT_SUBMODULES=(
	'*'
	'-lib/binaryen/third_party/googletest'
	'-lib/stm32-svd/stm32-rs'
	'-lib/wasi-libc/tools/wasi-headers/WASI'
)

inherit cmake git-r3 go-module llvm-r2

DESCRIPTION="TinyGo compiler for embedded systems and WebAssembly"
HOMEPAGE="https://tinygo.org/ https://github.com/tinygo-org/tinygo"
SRC_URI="https://github.com/llvm/llvm-project/releases/download/llvmorg-${COMPILER_RT_VERSION}/llvm-project-${COMPILER_RT_VERSION}.src.tar.xz"

LICENSE="Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD BSD-2 ISC MIT MPL-2.0 ZPL public-domain"
SLOT="0"
KEYWORDS=""
# The full upstream test suite needs board simulators and cross toolchains.
RESTRICT="test"

DEPEND="$(llvm_gen_dep '
	llvm-core/clang:${LLVM_SLOT}=
	llvm-core/llvm:${LLVM_SLOT}=[llvm_targets_AArch64,llvm_targets_ARM,llvm_targets_AVR,llvm_targets_RISCV,llvm_targets_WebAssembly,llvm_targets_X86]
')"
RDEPEND="
	${DEPEND}
	!dev-lang/tinygo-bin
	>=dev-lang/go-1.25.0
	<dev-lang/go-1.28
	$(llvm_gen_dep 'llvm-core/lld:${LLVM_SLOT}')
"
BDEPEND="
	>=dev-lang/go-1.25.0
	$(llvm_gen_dep 'llvm-core/llvm:${LLVM_SLOT}')
"

CMAKE_USE_DIR="${S}/lib/binaryen"
BUILD_DIR="${WORKDIR}/binaryen-build"
DOCS=( CHANGELOG.md README.md LICENSE )

src_unpack() {
	unpack ${A}
	git-r3_src_unpack
	go-module_live_vendor
}

src_prepare() {
	# Binaryen 116 needs the upstream GCC 16 compatibility fix.
	if ! grep -q 'directory_iterator_destruct' "${CMAKE_USE_DIR}/third_party/llvm-project/Path.cpp"; then
		pushd "${CMAKE_USE_DIR}" >/dev/null || die
		eapply "${FILESDIR}/binaryen-116-gcc16.patch"
		popd >/dev/null || die
	fi
	cmake_src_prepare
}

src_configure() {
	go-module_src_configure
	local mycmakeargs=(
		-DBUILD_STATIC_LIB=ON
		-DBUILD_TESTS=OFF
		-DENABLE_WERROR=OFF
	)
	cmake_src_configure
}

src_compile() {
	# Generate the device register bindings used by embedded targets.
	emake -f make/gen-device.mk GO=go gen-device
	cmake_build wasm-opt

	local llvm_cppflags llvm_ldflags
	llvm_cppflags=$(llvm-config --cppflags) || die
	llvm_ldflags=$(llvm-config --ldflags --libs --system-libs) || die
	export CGO_CPPFLAGS="${CGO_CPPFLAGS} ${llvm_cppflags}"
	export CGO_LDFLAGS="${CGO_LDFLAGS} ${llvm_ldflags}"
	ego build -mod=vendor -trimpath -buildvcs=true -o build/tinygo \
		-tags "llvm${LLVM_SLOT}" \
		-ldflags "-X github.com/tinygo-org/tinygo/goenv.TINYGOROOT=${EPREFIX}/usr/$(get_libdir)/tinygo" .
}

src_install() {
	local dest="/usr/$(get_libdir)/tinygo"
	dodir "${dest}/lib/CMSIS/CMSIS"

	# These directories are the runtime and target data required by TinyGo.
	local dir
	for dir in src targets; do
		cp -a "${S}/${dir}" "${ED}${dest}/" || die
	done
	for dir in bdwgc macos-minimal-sdk mingw-w64 musl nrfx picolibc wasi-cli wasi-libc xtensa; do
		cp -a "${S}/lib/${dir}" "${ED}${dest}/lib/" || die
	done
	cp -a lib/CMSIS/CMSIS/Include "${ED}${dest}/lib/CMSIS/CMSIS/" || die
	cp -a "${S}/lib/picolibc-stdio.c" "${ED}${dest}/lib/" || die
	cp -a "${WORKDIR}/llvm-project-${COMPILER_RT_VERSION}.src/compiler-rt/lib/builtins" \
		"${ED}${dest}/lib/compiler-rt-builtins" || die
	cp "${WORKDIR}/llvm-project-${COMPILER_RT_VERSION}.src/compiler-rt/LICENSE.TXT" \
		"${ED}${dest}/lib/compiler-rt-builtins/" || die
	find "${ED}${dest}" -name .git -prune -exec rm -r {} + || die

	exeinto "${dest}/bin"
	doexe build/tinygo
	doexe "${BUILD_DIR}/bin/wasm-opt"
	# Always use the LLVM slot matching the compiler's linked libraries.
	cat > "${T}/tinygo" <<-EOF || die
		#!/bin/sh
		export PATH="${EPREFIX}/usr/lib/llvm/${LLVM_SLOT}/bin:\${PATH}"
		exec "${EPREFIX}${dest}/bin/tinygo" "\$@"
	EOF
	newbin "${T}/tinygo" tinygo
	einstalldocs
}
