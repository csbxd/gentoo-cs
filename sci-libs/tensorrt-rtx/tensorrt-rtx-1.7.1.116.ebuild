# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="NVIDIA TensorRT for RTX native C++ inference SDK"
HOMEPAGE="https://developer.nvidia.com/tensorrt-rtx"
SRC_URI="https://developer.nvidia.com/downloads/trt/rtx_sdk/secure/$(ver_cut 1-2)/tensorrt-rtx-${PV}-linux-x86_64-cuda-13.4-release-external.tar.zst -> ${P}.tar.zst"
S="${WORKDIR}/TensorRT-RTX-${PV}"

LICENSE="NVIDIA-TensorRT-RTX"
SLOT="0/1.7"
KEYWORDS="~amd64"
RESTRICT="bindist mirror strip test"

RDEPEND=">=x11-drivers/nvidia-drivers-580 >=dev-util/nvidia-cuda-toolkit-13.4:="
BDEPEND="app-arch/zstd"

src_unpack() {
	tar --zstd -xf "${DISTDIR}/${P}.tar.zst" || die "SDK extraction failed"
}

src_install() {
	insinto /opt/tensorrt-rtx
	doins -r include lib cmake doc
	exeinto /opt/tensorrt-rtx/bin
	doexe bin/tensorrt_rtx
	dosym ../../opt/tensorrt-rtx/bin/tensorrt_rtx /usr/bin/tensorrt_rtx
	newenvd - 99tensorrt-rtx <<-EOF
		LDPATH="/opt/tensorrt-rtx/lib"
	EOF
}
