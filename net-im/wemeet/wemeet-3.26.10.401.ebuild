# Copyright 2023-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..15} )

inherit desktop python-any-r1 unpacker xdg

DESCRIPTION="Wemeet - Tencent Video Conferencing"
HOMEPAGE="https://meeting.tencent.com/"

SRC_URI="
	amd64? (
		https://updatecdn.meeting.qq.com/cos/72e0e0023e1d1e6d4123fba28821aea1/TencentMeeting_0300000000_${PV}_x86_64_default.publish.officialwebsite.deb
			-> ${P}_amd64.deb
	)
	arm64? (
		https://updatecdn.meeting.qq.com/cos/c06d6bc4a3370dbfb2f43bbc6ff8969e/TencentMeeting_0300000000_${PV}_arm64_default.publish.officialwebsite.deb
			-> ${P}_arm64.deb
		https://kojipkgs.fedoraproject.org/packages/qt5-qtwebengine/5.15.10/4.fc37/aarch64/qt5-qtwebengine-5.15.10-4.fc37.aarch64.rpm
			-> ${P}-qtwebengine.rpm
		https://kojipkgs.fedoraproject.org/packages/icu/71.1/2.fc37/aarch64/libicu-71.1-2.fc37.aarch64.rpm
			-> ${P}-libicu.rpm
		https://kojipkgs.fedoraproject.org/packages/libvpx/1.12.0/4.fc37/aarch64/libvpx-1.12.0-4.fc37.aarch64.rpm
			-> ${P}-libvpx.rpm
		https://kojipkgs.fedoraproject.org/packages/re2/20220601/1.fc37/aarch64/re2-20220601-1.fc37.aarch64.rpm
			-> ${P}-re2.rpm
	)
"

S="${WORKDIR}"
LICENSE="wemeet_license || ( GPL-2 GPL-3 LGPL-3 ) FDL-1.3 BSD"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror test"

RDEPEND="
	app-arch/snappy
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/libevent
	dev-libs/nspr
	dev-libs/nss
	dev-libs/wayland
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	media-libs/harfbuzz
	media-libs/lcms:2
	media-libs/libglvnd
	media-libs/libjpeg-turbo
	media-libs/libpng
	media-libs/libpulse
	media-libs/libwebp
	media-libs/opus
	sys-apps/dbus
	virtual/udev
	virtual/zlib
	x11-libs/libdrm
	x11-libs/libICE
	x11-libs/libSM
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXinerama
	x11-libs/libxkbcommon
	x11-libs/libXrandr
	x11-libs/libXrender
	x11-libs/libXtst
	x11-libs/xcb-util-image
	x11-libs/xcb-util-keysyms
	x11-libs/xcb-util-renderutil
	x11-libs/xcb-util-wm
	arm64? ( sys-apps/bubblewrap )
"
BDEPEND="
	dev-util/patchelf
	arm64? (
		app-arch/libarchive
		${PYTHON_DEPS}
	)
"

QA_PREBUILT="opt/${PN}/*"

pkg_setup() {
	use arm64 && python-any-r1_pkg_setup
}

src_unpack() {
	case ${ARCH} in
		amd64) unpack_deb "${DISTDIR}/${P}_amd64.deb" ;;
		arm64) unpack_deb "${DISTDIR}/${P}_arm64.deb" ;;
		*) die "unsupported architecture: ${ARCH}" ;;
	esac

	if use arm64; then
		local compat_dir="${WORKDIR}/qt5-webengine-16k"
		local rpm

		mkdir -p "${compat_dir}" || die
		for rpm in \
			${P}-qtwebengine.rpm \
			${P}-libicu.rpm \
			${P}-libvpx.rpm \
			${P}-re2.rpm; do
			einfo "Unpacking ${rpm}"
			bsdtar -xf "${DISTDIR}/${rpm}" -C "${compat_dir}" || die
		done
	fi
}

src_prepare() {
	local f

	einfo "Unbundling libraries"
	pushd opt/${PN}/lib > /dev/null || die
	for f in lib*; do
		case "${f#lib}" in
			desktop*|crash_guard*|ImSDK*|nxui*|qt*|service_manager*|tms*|ui*|wemeet*|xcast*|xnn*|yuv*|TencentSM*)
				continue
				;;
			icu*|jpeg.so.8*|Qt5*)
				continue
				;;
		esac
		einfo "  ${f}"
		rm "${f}" || die
	done
	popd > /dev/null || die

	einfo "Unbundling plugins to fix libqxcb-glx-integration SIGSEGV"
	rm -r opt/${PN}/plugins/xcbglintegrations || die

	default
}

src_install() {
	local f

	# Fix RPATHs to ensure the bundled application libraries can be found.
	while IFS= read -r -d '' f; do
		[[ $(od -t x1 -N 4 "${f}") == *"7f 45 4c 46"* ]] || continue
		patchelf --set-rpath "/opt/${PN}/lib" "${f}" || die
	done < <(find "opt/${PN}/bin" "opt/${PN}/plugins" -type f -print0)

	while IFS= read -r -d '' f; do
		[[ $(od -t x1 -N 4 "${f}") == *"7f 45 4c 46"* ]] || continue
		patchelf --set-rpath '$ORIGIN' "${f}" || die
	done < <(find "opt/${PN}/lib" -type f -print0)

	if use arm64; then
		# The upstream ARM64 libImSDK has 4 KiB-congruent PT_LOAD segments and
		# cannot be mapped by a 16 KiB kernel.  Repack after patchelf so the
		# final installed ELF, including its new RUNPATH segment, is congruent.
		"${EPYTHON}" "${FILESDIR}/align-elf-16k.py" \
			"opt/${PN}/lib/libImSDK.so" "${T}/libImSDK.so" || die
		mv "${T}/libImSDK.so" "opt/${PN}/lib/libImSDK.so" || die
	fi

	insinto "/opt/${PN}"
	doins -r opt/${PN}/*

	exeinto "/opt/${PN}"
	newexe "${FILESDIR}/wemeetapp-xwayland.sh" wemeetapp.sh
	fperms +x "/opt/${PN}/bin/wemeetapp"
	fperms +x "/opt/${PN}/bin/QtWebEngineProcess"

	if use arm64; then
		local compat_src="${WORKDIR}/qt5-webengine-16k/usr"
		local compat_dest="/opt/${PN}/qt5-webengine-16k"

		# Only expose the patched Core to Wemeet.  Fedora's WebEngineWidgets is
		# ABI-incompatible with Tencent's customized QtWidgets and crashes in
		# QWidget::~QWidget().
		insinto "${compat_dest}/lib"
		newins "${compat_src}/lib64/libQt5WebEngineCore.so.5.15.10" \
			libQt5WebEngineCore.so.5.15.10
		newins "${compat_src}/lib64/libicudata.so.71.1" libicudata.so.71.1
		newins "${compat_src}/lib64/libicui18n.so.71.1" libicui18n.so.71.1
		newins "${compat_src}/lib64/libicuuc.so.71.1" libicuuc.so.71.1
		newins "${compat_src}/lib64/libre2.so.9.0.0" libre2.so.9.0.0
		newins "${compat_src}/lib64/libvpx.so.7.1.0" libvpx.so.7.1.0

		dosym libQt5WebEngineCore.so.5.15.10 \
			"${compat_dest}/lib/libQt5WebEngineCore.so.5"
		dosym libicudata.so.71.1 "${compat_dest}/lib/libicudata.so.71"
		dosym libicui18n.so.71.1 "${compat_dest}/lib/libicui18n.so.71"
		dosym libicuuc.so.71.1 "${compat_dest}/lib/libicuuc.so.71"
		dosym libre2.so.9.0.0 "${compat_dest}/lib/libre2.so.9"
		dosym libvpx.so.7.1.0 "${compat_dest}/lib/libvpx.so.7"

		exeinto "${compat_dest}/libexec"
		doexe "${compat_src}/lib64/qt5/libexec/QtWebEngineProcess"

		insinto "${compat_dest}/resources"
		doins "${compat_src}"/share/qt5/resources/qtwebengine_resources*.pak
		# The Fedora build does not ship the devtools pak.  It is compatible
		# with Chromium 87 and is retained from the Tencent distribution.
		doins opt/${PN}/resources/qtwebengine_devtools_resources.pak

		insinto "${compat_dest}/translations/qtwebengine_locales"
		doins "${compat_src}"/share/qt5/translations/qtwebengine_locales/*.pak
	fi

	dosym "../../opt/${PN}/wemeetapp.sh" /usr/bin/wemeetapp

	sed -i "s/^Icon=.*/Icon=wemeetapp/g" \
		usr/share/applications/wemeetapp.desktop || die
	sed -i "s/^Exec=.*/Exec=wemeetapp %u/g" \
		usr/share/applications/wemeetapp.desktop || die
	sed -i -e '$a Comment=Tencent Meeting Linux Client\n\' \
		-e 'Comment[zh_CN]=腾讯会议Linux客户端\n\' \
		-e 'Keywords=wemeet;tencent;meeting;\n' \
		usr/share/applications/wemeetapp.desktop || die
	domenu usr/share/applications/wemeetapp.desktop
	newicon -s scalable opt/${PN}/wemeet.svg wemeetapp.svg

	local i png_file
	for i in 16 32 64 128 256; do
		png_file="opt/${PN}/icons/hicolor/${i}x${i}/mimetypes/wemeetapp.png"
		[[ -e ${png_file} ]] && newicon -s "${i}" -c mimetypes \
			"${png_file}" wemeetapp.png
	done
}
