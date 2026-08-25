# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop unpacker xdg

DESCRIPTION="Baidu Net Disk cloud storage client"
HOMEPAGE="https://pan.baidu.com/"
SRC_URI="https://issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/${PV}/${PN}_${PV}_arm64.deb"

S="${WORKDIR}"

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

src_prepare() {
	sed -e 's|^Exec=.*|Exec=baidunetdisk --no-sandbox %U|' \
		-e '/^Name=/a Name[zh_CN]=百度网盘' \
		-i usr/share/applications/${PN}.desktop || die
	default
}

src_install() {
	insinto /opt
	doins -r opt/${PN}
	fperms +x /opt/${PN}/${PN}
	fperms +x \
		/opt/${PN}/resources/app.asar.unpacked/node_modules/@baidu/clipboard-listen-macos/clipboard_linux \
		/opt/${PN}/resources/app.asar.unpacked/node_modules/@baidu/clipboard-listen-macos/src/clipboard_linux/clipboard_linux
	dosym -r /opt/${PN}/${PN} /usr/bin/${PN}

	gzip -d usr/share/doc/${PN}/*.gz || die
	dodoc usr/share/doc/${PN}/*

	domenu usr/share/applications/${PN}.desktop
	doicon -s scalable usr/share/icons/hicolor/scalable/apps/${PN}.svg
}
