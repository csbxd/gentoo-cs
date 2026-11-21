# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
inherit cmake

DESCRIPTION="Configurable Bilibili RIFE interpolation browser extension and native host"
HOMEPAGE="https://github.com/csbxd/modeld"
SRC_URI="
	https://github.com/csbxd/modeld/releases/download/v${PV}/modeld-${PV}.tar.gz
	https://github.com/csbxd/modeld/releases/download/v${PV}/modeld-browser-${PV}.crx
"
S="${WORKDIR}/modeld-${PV}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="+chrome chromium test"
REQUIRED_USE="|| ( chrome chromium )"
RESTRICT="!test? ( test )"

COMMON_DEPEND="dev-cpp/cpp-httplib:=[ssl] dev-libs/openssl:="
DEPEND="${COMMON_DEPEND} dev-cpp/nlohmann_json"
RDEPEND="${COMMON_DEPEND}"
BDEPEND="virtual/pkgconfig test? ( >=net-libs/nodejs-22 )"

src_configure() {
	local mycmakeargs=(
		-DMODELD_CLIENT=OFF
		-DMODELD_SERVER=OFF
		-DMODELD_BROWSER=ON
		-DBUILD_TESTING=$(usex test)
	)
	cmake_src_configure
}

src_test() {
	cmake_src_test
	MODELD_BROWSER_HOST="${BUILD_DIR}/modeld-browser-host" node --test tests/browser*.test.mjs || die
}

src_install() {
	cmake_src_install
	insinto /usr/share/modeld
	newins "${DISTDIR}/modeld-browser-${PV}.crx" browser.crx

	sed "s|/usr/bin/modeld-browser-host|${EPREFIX}/usr/bin/modeld-browser-host|" \
		browser/native-host.json > "${T}/native-host.json" || die
	if use chrome; then
		insinto /etc/opt/chrome/native-messaging-hosts
		newins "${T}/native-host.json" org.csbxd.modeld.browser.json
		insinto /etc/opt/chrome/policies/managed
		newins browser/chrome-policy.json modeld-browser.json
	fi
	if use chromium; then
		insinto /etc/chromium/native-messaging-hosts
		newins "${T}/native-host.json" org.csbxd.modeld.browser.json
		insinto /etc/chromium/policies/managed
		newins browser/chrome-policy.json modeld-browser.json
	fi
	docinto docs
	dodoc docs/browser.md docs/api.md docs/architecture.md
}

pkg_postinst() {
	elog "Requires modeld >= 2.1 on your GPU server. Existing modeld connection settings are inherited."
	elog "Independent AV1 VBR bitrate settings require modeld >= 2.1.7, AV1 NVENC and a browser with AV1 MediaSource support."
	elog "Chrome installs the signed extension through its Linux policy/update mechanism."
	elog "Refresh Bilibili pages or restart the browser after installation."
	elog "Use the page's interpolation button or Alt+Shift+i; settings are available from the extension."
	elog "API credentials stay in private local files. No Python, mpv or CUDA is needed in the browser host."
}
