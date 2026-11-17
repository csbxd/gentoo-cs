# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="RIFE 4.26 Heavy packed FP32 ONNX model for modeld"
HOMEPAGE="https://github.com/hzwer/Practical-RIFE https://github.com/AmusementClub/vs-mlrt"
SRC_URI="https://github.com/AmusementClub/vs-mlrt/releases/download/external-models/rife_v${PV}_heavy.7z -> ${P}.7z"
S="${WORKDIR}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
RESTRICT="test"
BDEPEND="app-arch/7zip"

src_unpack() {
	7z x "${DISTDIR}/${P}.7z" || die "Model extraction failed"
}

src_install() {
	insinto /usr/share/modeld/models
	newins rife_v2/rife_v${PV}_heavy.onnx rife-${PV}-heavy.onnx
}
