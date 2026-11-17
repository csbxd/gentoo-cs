# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
inherit cmake

DESCRIPTION="Native mpv plugin for remote modeld frame interpolation"
HOMEPAGE="https://github.com/csbxd/modeld"
SRC_URI="https://github.com/csbxd/modeld/releases/download/v${PV}/modeld-${PV}.tar.gz"
S="${WORKDIR}/modeld-${PV}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="test"
RESTRICT="!test? ( test )"
DEPEND="dev-cpp/cpp-httplib:= dev-cpp/nlohmann_json dev-libs/openssl:= media-video/mpv[libmpv]"
RDEPEND="${DEPEND}"
BDEPEND="virtual/pkgconfig"

src_configure() {
	local mycmakeargs=(
		-DMODELD_CLIENT=ON
		-DMODELD_SERVER=OFF
		-DBUILD_TESTING=$(usex test)
	)
	cmake_src_configure
}

pkg_postinst() {
	elog "Link /usr/$(get_libdir)/mpv/scripts/modeld.so into ~/.config/mpv/scripts/."
	elog "Configure ~/.config/modeld/client.json and a private API token file."
	elog "Ctrl+Shift+i toggles interpolation; each newly opened file starts with the original video."
}
