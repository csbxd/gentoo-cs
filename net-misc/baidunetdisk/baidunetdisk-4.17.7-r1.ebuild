# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop unpacker xdg

MY_ELECTRON_RELEASE="11.3.0-16k.1"
MY_ELECTRON_FILE="electron-v11.3.0-linux-arm64-16k.tar.xz"

DESCRIPTION="Baidu Net Disk cloud storage client"
HOMEPAGE="https://pan.baidu.com/"
SRC_URI="
	https://issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/${PV}/${PN}_${PV}_arm64.deb
	https://github.com/csbxd/electron11-16k/releases/download/v${MY_ELECTRON_RELEASE}/${MY_ELECTRON_FILE}
"

S="${WORKDIR}/baidu"

LICENSE="BaiduNetDisk"
SLOT="0"
KEYWORDS="-* ~arm64"

RESTRICT="bindist mirror strip"

RDEPEND="
	app-accessibility/at-spi2-core
	app-crypt/libsecret
	app-crypt/p11-kit
	dev-libs/nss
	media-libs/alsa-lib
	sys-apps/util-linux
	x11-libs/gtk+:3[cups]
	x11-libs/libnotify
	x11-libs/libXScrnSaver
	x11-libs/libXtst
	x11-misc/xdg-utils
"

QA_PREBUILT="*"

src_unpack() {
	mkdir -p "${WORKDIR}"/{baidu,electron} || die

	pushd "${WORKDIR}/baidu" >/dev/null || die
	unpack_deb "${DISTDIR}/${PN}_${PV}_arm64.deb"
	popd >/dev/null || die

	pushd "${WORKDIR}/electron" >/dev/null || die
	unpack "${MY_ELECTRON_FILE}"
	popd >/dev/null || die
}

replace_electron_runtime() {
	local app_root="${S}/opt/${PN}"
	local runtime_root="${WORKDIR}/electron"
	local runtime_file
	local -a runtime_files=(
		chrome-sandbox
		chrome_100_percent.pak
		chrome_200_percent.pak
		icudtl.dat
		libEGL.so
		libGLESv2.so
		libffmpeg.so
		libvk_swiftshader.so
		libvulkan.so
		resources.pak
		snapshot_blob.bin
		v8_context_snapshot.bin
		version
		vk_swiftshader_icd.json
	)

	cp -a "${runtime_root}/electron" "${app_root}/${PN}" || die
	for runtime_file in "${runtime_files[@]}"; do
		cp -a "${runtime_root}/${runtime_file}" "${app_root}/${runtime_file}" || die
	done

	rm -rf "${app_root}"/{locales,swiftshader} || die
	cp -a "${runtime_root}"/{locales,swiftshader} "${app_root}/" || die
	cp -a "${runtime_root}/LICENSE" "${app_root}/LICENSE.electron.txt" || die
	cp -a "${runtime_root}/LICENSES.chromium.html" "${app_root}/" || die
}

src_prepare() {
	default
	replace_electron_runtime

	sed -e 's|^Exec=.*|Exec=baidunetdisk %U|' \
		-e '/^Name=/a Name[zh_CN]=百度网盘' \
		-i usr/share/applications/${PN}.desktop || die
}

src_install() {
	insinto /opt
	doins -r opt/${PN}
	fperms +x /opt/${PN}/${PN}
	fperms +x \
		/opt/${PN}/resources/app.asar.unpacked/node_modules/@baidu/clipboard-listen-macos/clipboard_linux \
		/opt/${PN}/resources/app.asar.unpacked/node_modules/@baidu/clipboard-listen-macos/src/clipboard_linux/clipboard_linux
	newbin "${FILESDIR}/${PN}.sh" "${PN}"

	gzip -d usr/share/doc/${PN}/*.gz || die
	dodoc usr/share/doc/${PN}/*

	domenu usr/share/applications/${PN}.desktop
	doicon -s scalable usr/share/icons/hicolor/scalable/apps/${PN}.svg
}
