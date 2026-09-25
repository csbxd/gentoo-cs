# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop optfeature pax-utils unpacker xdg

MY_PN="chatgpt"
OAI_BASE="https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/${MY_PN}"

DESCRIPTION="OpenAI Codex desktop application for Linux"
HOMEPAGE="https://developers.openai.com/codex/app"
SRC_URI="
	amd64? ( ${OAI_BASE}/${MY_PN}_${PV}_amd64.deb -> ${P}-amd64.deb )
	arm64? ( ${OAI_BASE}/${MY_PN}_${PV}_arm64.deb -> ${P}-arm64.deb )
"
S="${WORKDIR}"

LICENSE="all-rights-reserved MIT"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="apparmor egl wayland"
RESTRICT="bindist mirror strip"

RDEPEND="
	app-accessibility/at-spi2-core:2
	app-arch/xz-utils
	app-crypt/tpm2-tss
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2[utils]
	dev-libs/libusb:1
	dev-libs/nspr
	dev-libs/nss
	dev-libs/openssl:0/3
	media-gfx/graphite2
	media-libs/alsa-lib
	media-libs/libglvnd
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	virtual/libudev:=
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libdrm
	x11-libs/libnotify
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libxkbcommon
	x11-libs/libXrandr
	x11-libs/pango
	x11-misc/xdg-utils
	apparmor? ( sys-apps/apparmor )
"

BDEPEND="app-arch/xz-utils"
QA_PREBUILT="*"

APP_SRCDIR="usr/lib/${MY_PN}"
APP_DESTDIR="/usr/lib/${MY_PN}"

src_install() {
	dodir "${APP_DESTDIR}"
	cp -a "${APP_SRCDIR}/." "${ED}${APP_DESTDIR}/" || die

	# The Electron build uses unprivileged user namespaces and ships no
	# setuid chrome-sandbox helper.
	pax-mark m "${ED}${APP_DESTDIR}/ChatGPT"

	# Apply USE flags in the shared launcher for both desktop and CLI starts.
	# The bundled runtime ignores --ozone-platform-hint=auto and defaults to X11.
	sed -e "s|@WAYLAND@|$(usex wayland yes no)|g" \
		-e "s|@EGL@|$(usex egl yes no)|g" \
		"${FILESDIR}/codex-launcher" > "${T}/codex-launcher" || die
	exeinto "${APP_DESTDIR}"
	doexe "${T}/codex-launcher"

	dosym -r "${APP_DESTDIR}/codex-launcher" "/usr/bin/${MY_PN}"
	dosym -r "${APP_DESTDIR}/codex-launcher" "/usr/bin/${PN%-bin}"

	newmenu "usr/share/applications/${MY_PN}.desktop" "${PN%-bin}.desktop"

	newicon -s 1024 "usr/share/pixmaps/${MY_PN}.png" "${MY_PN}.png"

	if use apparmor; then
		insinto /etc/apparmor.d
		doins "etc/apparmor.d/${MY_PN}"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	einfo "The desktop application is available as 'chatgpt' and 'codex-desktop'."
	einfo "This preview requires unprivileged user namespaces for its renderer sandbox."

	optfeature "repository operations from Codex" dev-vcs/git
	optfeature "system tray icon" dev-libs/libayatana-appindicator
	optfeature "audio playback" media-libs/libpulse
}
