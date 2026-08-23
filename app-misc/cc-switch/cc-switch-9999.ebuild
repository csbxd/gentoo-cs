# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the MIT License

EAPI=8

inherit desktop git-r3 xdg

DESCRIPTION="All-in-One assistant tool for Claude Code, Codex, OpenCode, openclaw & Gemini CLI"
HOMEPAGE="https://github.com/farion1231/cc-switch"
EGIT_REPO_URI="https://github.com/farion1231/cc-switch.git"

LICENSE="MIT"
SLOT="0"
KEYWORDS=""

# Building Tauri apps requires downloading node modules and cargo crates.
# Standard Gentoo practice is to vendor them, but for a personal overlay
# and this complex build, we'll allow network access during build.
RESTRICT="network-sandbox"

RDEPEND="
	dev-libs/glib:2
	dev-libs/libayatana-appindicator
	dev-libs/openssl:0/3
	net-libs/libsoup:3.0
	net-libs/webkit-gtk:4.1
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/pango
	x11-themes/hicolor-icon-theme
"

BDEPEND="
	net-libs/nodejs
	sys-apps/pnpm
	|| ( dev-lang/rust dev-lang/rust-bin )
	x11-misc/xdg-utils
	dev-vcs/git
"

src_prepare() {
	default

	# pnpm 11 aborts on unapproved dependency build scripts.
	cat > pnpm-workspace.yaml <<-'EOF' || die
	packages: []

	allowBuilds:
	  esbuild: true
	  msw: true

	onlyBuiltDependencies:
	  - '@tailwindcss/oxide'
	  - esbuild
	  - msw
	EOF
}

src_compile() {
	export CARGO_TARGET_DIR="${S}/target"
	export pnpm_config_store_dir="${T}/pnpm-store"
	export XDG_CACHE_HOME="${T}/xdg-cache"
	# fix for static link (following PKGBUILD)
	unset CFLAGS CXXFLAGS LDFLAGS

	pnpm install --frozen-lockfile || die
	pnpm tauri build --no-bundle || die
}

src_install() {
	dobin "${S}/target/release/${PN}"
	
	newicon -s 128 src-tauri/icons/128x128.png com.ccswitch.desktop.png
	newicon -s 32 src-tauri/icons/32x32.png com.ccswitch.desktop.png
	
	# HiDPI icon
	insinto /usr/share/icons/hicolor/256x256@2/apps
	newins src-tauri/icons/128x128@2x.png com.ccswitch.desktop.png
	
	domenu flatpak/com.ccswitch.desktop.desktop
	
	einstalldocs
	dodoc LICENSE
}
