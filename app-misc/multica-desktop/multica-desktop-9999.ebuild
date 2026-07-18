# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

EGIT_REPO_URI="https://github.com/multica-ai/multica.git"

inherit desktop git-r3 xdg

DESCRIPTION="Native desktop client for the Multica platform"
HOMEPAGE="https://multica.ai https://github.com/multica-ai/multica"

LICENSE="Multica"
SLOT="0"
KEYWORDS=""

RESTRICT="network-sandbox strip splitdebug"
QA_PREBUILT="/opt/${PN}/*"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	dev-libs/wayland
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	sys-apps/util-linux
	sys-libs/glibc
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libX11
	x11-libs/libXScrnSaver
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libdrm
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/libxshmfence
	x11-libs/pango
	x11-misc/xdg-utils
	x11-themes/hicolor-icon-theme
"
BDEPEND="
	>=dev-lang/go-1.26.1:=
	dev-vcs/git
	net-libs/nodejs
	>=sys-apps/pnpm-bin-10.28.2
	<sys-apps/pnpm-bin-11
"

src_compile() {
	export ELECTRON_CACHE="${T}/electron-cache"
	export GOCACHE="${T}/go-cache"
	export GOMODCACHE="${T}/go-mod"
	export npm_config_cache="${T}/npm-cache"
	export pnpm_config_store_dir="${T}/pnpm-store"
	export XDG_CACHE_HOME="${T}/xdg-cache"

	pnpm install --frozen-lockfile || die
	pnpm -C apps/desktop package -- --linux dir || die
}

src_install() {
	local appdir dest size
	local unpacked_dirs=( apps/desktop/dist/linux*unpacked )

	appdir="${unpacked_dirs[0]}"
	[[ -d "${appdir}" ]] || die "Could not find electron-builder linux-unpacked output"

	dest="/opt/${PN}"
	insinto "${dest}"
	doins -r "${appdir}"/*

	fperms +x "${dest}/multica"
	[[ -f "${ED}${dest}/chrome_crashpad_handler" ]] && fperms +x "${dest}/chrome_crashpad_handler"
	[[ -f "${ED}${dest}/resources/bin/multica" ]] && fperms +x "${dest}/resources/bin/multica"
	if [[ -f "${ED}${dest}/chrome-sandbox" ]]; then
		fowners root "${dest}/chrome-sandbox"
		fperms 4711 "${dest}/chrome-sandbox"
	fi

	dosym -r "${dest}/multica" "/usr/bin/${PN}"

	for size in 16 24 32 48 64 128 256 512; do
		newicon -s "${size}" "apps/desktop/build/icons/${size}x${size}.png" "${PN}.png"
	done
	make_desktop_entry "${PN} %U" "Multica" "${PN}" "Network;Development;" \
		"StartupWMClass=Multica\nMimeType=x-scheme-handler/multica;"

	dodoc README.md README.zh-CN.md CLI_INSTALL.md CLI_AND_DAEMON.md LICENSE
}
