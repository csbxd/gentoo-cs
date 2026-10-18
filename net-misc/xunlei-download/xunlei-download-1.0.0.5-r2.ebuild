# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop unpacker xdg

MY_PN="com.${PN/-/.}"
MY_ELECTRON_FILE="electron-v1.8.6-linux-arm64-16k.tar.xz"
MY_ELECTRON_RELEASE="electron-1.8.6-16k.1"

DESCRIPTION="Xunlei download client with a 16 KiB compatible Electron runtime"
HOMEPAGE="https://www.xunlei.com/"
SRC_URI="
	https://archive2.kylinos.cn/DEB/KYLIN_DEB/pool/all/${MY_PN}_${PV}_arm64.deb
	https://github.com/csbxd/gentoo-cs/releases/download/${MY_ELECTRON_RELEASE}/${MY_ELECTRON_FILE}
"
S="${WORKDIR}/xunlei/opt/apps/${MY_PN}"

LICENSE="com.xunlei.download MIT BSD BSD-2 LGPL-2.1+"
SLOT="0"
KEYWORDS="-* ~arm64"
REQUIRED_USE="elibc_glibc"
RESTRICT="bindist mirror strip"

BDEPEND="dev-util/patchelf"

RDEPEND="
	app-accessibility/at-spi2-core:2
	dev-libs/dbus-glib
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/libglvnd[X]
	media-libs/freetype
	net-print/cups
	sys-apps/dbus
	>=sys-libs/glibc-2.27
	virtual/libudev
	x11-libs/cairo[X]
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:2
	x11-libs/libX11
	x11-libs/libXcomposite
	x11-libs/libXcursor
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXi
	x11-libs/libXrandr
	x11-libs/libXrender
	x11-libs/libXScrnSaver
	x11-libs/libXtst
	x11-libs/libxcb
	x11-libs/pango
	x11-misc/xdg-utils
"

QA_PREBUILT="*"

src_unpack() {
	mkdir -p "${WORKDIR}"/{xunlei,electron} || die

	pushd "${WORKDIR}/xunlei" >/dev/null || die
	unpack_deb "${DISTDIR}/${MY_PN}_${PV}_arm64.deb"
	popd >/dev/null || die

	pushd "${WORKDIR}/electron" >/dev/null || die
	unpack "${MY_ELECTRON_FILE}"
	popd >/dev/null || die
}

replace_electron_runtime() {
	local runtime_root="${WORKDIR}/electron"
	local runtime_file
	local -a runtime_files=(
		blink_image_resources_200_percent.pak
		content_resources_200_percent.pak
		content_shell.pak
		icudtl.dat
		libffmpeg.so
		libnode.so
		natives_blob.bin
		pdf_viewer_resources.pak
		snapshot_blob.bin
		ui_resources_200_percent.pak
		version
		views_resources_200_percent.pak
	)

	# Preserve the upstream app, native add-ons, SDK and bundled GConf library.
	cp -a "${runtime_root}/electron" files/thunder || die
	for runtime_file in "${runtime_files[@]}"; do
		cp -a "${runtime_root}/${runtime_file}" "files/${runtime_file}" || die
	done

	rm -rf files/locales || die
	cp -a "${runtime_root}/locales" files/ || die
	cp -a "${runtime_root}/resources/electron.asar" files/resources/ || die
	cp -a "${runtime_root}/LICENSE" files/LICENSE.electron.txt || die
	cp -a "${runtime_root}/LICENSES.chromium.html" files/ || die
}

src_prepare() {
	default
	replace_electron_runtime

	# The launcher supplies the SDK library directory. Drop upstream build-host
	# paths without adding ELF segments or changing executable code.
	local vendor_elf
	for vendor_elf in files/resources/bin/ThunderKernel.node files/libxl_thunder_sdk.so; do
		patchelf --remove-rpath "${vendor_elf}" || die
	done

	sed -e '/^Categories=/c Categories=Network;FileTransfer;' \
		-e '/^Exec=/c Exec=xunlei-download %U' \
		-e '/^Icon=/c Icon=com.xunlei.download' \
		-i entries/applications/${MY_PN}.desktop || die
}

src_install() {
	insinto /opt/${PN}
	doins -r files/*
	newins "${FILESDIR}/${PN}.sh" start.sh
	fperms +x /opt/${PN}/{start.sh,thunder,libnode.so,resources/bin/{ThunderHelper.node,ThunderKernel.node}}
	newbin "${FILESDIR}/${PN}.sh" "${PN}"

	local size
	for size in 16 24 32 48 128 256; do
		doicon -s ${size} entries/icons/hicolor/${size}x${size}/apps/${MY_PN}.png
	done
	newicon -s scalable entries/icons/hicolor/scalable/apps/com.thunder.download.svg ${MY_PN}.svg
	domenu entries/applications/${MY_PN}.desktop
}
