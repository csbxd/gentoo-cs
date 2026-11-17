# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="NVIDIA TensorRT native C++ inference SDK"
HOMEPAGE="https://developer.nvidia.com/tensorrt https://github.com/NVIDIA/TensorRT"
SRC_URI="https://developer.nvidia.com/downloads/compute/machine-learning/tensorrt/$(ver_cut 1-3)/tars/TensorRT-Enterprise-${PV}-Linux-x86_64-cuda-13.4-Release-external.tar.zst -> ${P}.tar.zst"
S="${WORKDIR}/TensorRT-${PV}"

LICENSE="NVIDIA-SDK-v2020.10.12 Apache-2.0"
SLOT="0/11"
KEYWORDS="~amd64"
IUSE="+tools"
RESTRICT="bindist mirror strip test"

RDEPEND=">=x11-drivers/nvidia-drivers-580 >=dev-util/nvidia-cuda-toolkit-13.4:="
BDEPEND="app-arch/zstd"
QA_PREBUILT="opt/tensorrt/bin/* opt/tensorrt/lib/*"

src_unpack() {
	tar --zstd -xf "${DISTDIR}/${P}.tar.zst" || die "SDK extraction failed"
}

src_install() {
	insinto /opt/tensorrt
	doins -r include lib cmake doc
	if use tools; then
		exeinto /opt/tensorrt/bin
		doexe bin/trtexec bin/tensorrt_player
		# Isolate the SDK's shim and builder libraries from TensorRT-RTX.
		cat > "${T}/trtexec" <<-EOF || die
			#!/bin/sh
			export LD_LIBRARY_PATH="${EPREFIX}/opt/tensorrt/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
			exec "${EPREFIX}/opt/tensorrt/bin/trtexec" "\$@"
		EOF
		dobin "${T}/trtexec"
	fi
}

pkg_postinst() {
	elog "C++ headers and libraries are installed in /opt/tensorrt."
	elog "Set the library path or RPATH per application; no global loader paths are changed."
}
