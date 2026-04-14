# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker xdg

MY_MAIN_DEB="cloud189_uos_v1.0.0_arm64(20231030174214).deb"
MY_APPINDICATOR_DEB="libappindicator3-1_12.10.1+20.04.20200408.1-0ubuntu1_arm64.deb"
MY_ICU_DEB="libicu67_67.1-7_arm64.deb"
MY_JAVASCRIPTCORE_DEB="libjavascriptcoregtk-4.0-18_2.44.2-1~deb11u1_arm64.deb"
MY_JSONCPP_DEB="libjsoncpp1_1.7.4-3.1ubuntu2_arm64.deb"
MY_MANETTE_DEB="libmanette-0.2-0_0.2.5-1_arm64.deb"
MY_SOUP_DEB="libsoup2.4-1_2.72.0-2_arm64.deb"
MY_SSL_DEB="libssl1.1_1.1.1w-0+deb11u1_arm64.deb"
MY_WEBKIT_DEB="libwebkit2gtk-4.0-37_2.44.2-1~deb11u1_arm64.deb"
MY_WEBP_DEB="libwebp6_0.6.1-2.1+deb11u2_arm64.deb"
MY_XML2_DEB="libxml2_2.9.10+dfsg-6.7+deb11u4_arm64.deb"

DESCRIPTION="China Telecom ECloud desktop client"
HOMEPAGE="https://cloud.189.cn/"
SRC_URI="
	arm64? (
		https://ports.ubuntu.com/ubuntu-ports/pool/main/liba/libappindicator/${MY_APPINDICATOR_DEB}
		https://deb.debian.org/debian/pool/main/i/icu/${MY_ICU_DEB}
		https://deb.debian.org/debian/pool/main/w/webkit2gtk/${MY_JAVASCRIPTCORE_DEB}
		https://ports.ubuntu.com/ubuntu-ports/pool/main/libj/libjsoncpp/${MY_JSONCPP_DEB}
		https://deb.debian.org/debian/pool/main/libm/libmanette/${MY_MANETTE_DEB}
		https://deb.debian.org/debian/pool/main/libs/libsoup2.4/${MY_SOUP_DEB}
		https://deb.debian.org/debian/pool/main/o/openssl/${MY_SSL_DEB}
		https://deb.debian.org/debian/pool/main/w/webkit2gtk/${MY_WEBKIT_DEB}
		https://deb.debian.org/debian/pool/main/libw/libwebp/${MY_WEBP_DEB}
		https://deb.debian.org/debian/pool/main/libx/libxml2/${MY_XML2_DEB}
	)
"
S="${WORKDIR}"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="~arm64"

RESTRICT="mirror splitdebug strip"

RDEPEND="
	app-crypt/libsecret
	app-text/enchant:2
	dev-libs/libdbusmenu[gtk3]
	media-libs/alsa-lib
	media-libs/gst-plugins-base:1.0
	media-libs/gstreamer:1.0
	sys-libs/libseccomp
	x11-libs/gtk+:3
	x11-libs/libnotify
"
BDEPEND="app-arch/xz-utils"

QA_PREBUILT="
	/opt/ecloud/ecloud
	/opt/ecloud/lib/*
	/opt/ecloud/compat/lib/*
	/opt/ecloud/compat/webkit2gtk-4.0/*
	/opt/ecloud/compat/webkit2gtk-4.0/injected-bundle/*
"
QA_TEXTRELS="
	/opt/ecloud/lib/libfastplayer.so
"

PATCHED_WEBKIT_ROOT="/opt/ecloud/compat/webkit2gtk-4.0"
PATCHED_WEBKIT_BUNDLE_ROOT="${PATCHED_WEBKIT_ROOT}/injected-bundle/"

src_unpack() {
	local compat_debs=(
		"${MY_APPINDICATOR_DEB}"
		"${MY_ICU_DEB}"
		"${MY_JAVASCRIPTCORE_DEB}"
		"${MY_JSONCPP_DEB}"
		"${MY_MANETTE_DEB}"
		"${MY_SOUP_DEB}"
		"${MY_SSL_DEB}"
		"${MY_WEBKIT_DEB}"
		"${MY_WEBP_DEB}"
		"${MY_XML2_DEB}"
	)
	local deb
	local main_deb=
	local ro_dir

	mkdir -p "${WORKDIR}/main" "${WORKDIR}/compat" || die

	if [[ -n "${ECLOUD_MAIN_DEB:-}" && -f "${ECLOUD_MAIN_DEB}" ]]; then
		main_deb="${ECLOUD_MAIN_DEB}"
	elif [[ -f "${DISTDIR}/${MY_MAIN_DEB}" ]]; then
		main_deb="${DISTDIR}/${MY_MAIN_DEB}"
	else
		for ro_dir in ${PORTAGE_RO_DISTDIRS}; do
			if [[ -f "${ro_dir}/${MY_MAIN_DEB}" ]]; then
				main_deb="${ro_dir}/${MY_MAIN_DEB}"
				break
			fi
		done
	fi

	[[ -n "${main_deb}" ]] || die \
		"Missing ${MY_MAIN_DEB}; set ECLOUD_MAIN_DEB or put it in DISTDIR (${DISTDIR})"

	pushd "${WORKDIR}/main" >/dev/null || die
	unpack_deb "${main_deb}"
	popd >/dev/null || die

	pushd "${WORKDIR}/compat" >/dev/null || die
	for deb in "${compat_debs[@]}"; do
		unpack_deb "${DISTDIR}/${deb}"
	done
	popd >/dev/null || die
}

patch_webkit_paths() {
	local lib=$1

	# libwebkit2gtk-4.0.so.37.68.6 hardcodes Debian runtime helper paths.
	printf '%s\0' "${PATCHED_WEBKIT_ROOT}" | \
		dd of="${lib}" bs=1 seek=57321976 conv=notrunc status=none || die
	printf '%s\0' "${PATCHED_WEBKIT_BUNDLE_ROOT}" | \
		dd of="${lib}" bs=1 seek=57461288 conv=notrunc status=none || die
}

src_install() {
	local app_src="${WORKDIR}/main/opt/apps/com.dlife.ecloud/files"
	local icon_src="${WORKDIR}/main/opt/apps/com.dlife.ecloud/entries/icons/hicolor"
	local compat_src="${WORKDIR}/compat/usr/lib/aarch64-linux-gnu"
	local compat_lib_dst="${ED}/opt/ecloud/compat/lib"
	local compat_webkit_dst="${ED}/opt/ecloud/compat/webkit2gtk-4.0"
	local compat_files=(
		libappindicator3.so.1
		libappindicator3.so.1.0.0
		libcrypto.so.1.1
		libicudata.so.67
		libicudata.so.67.1
		libicui18n.so.67
		libicui18n.so.67.1
		libicuuc.so.67
		libicuuc.so.67.1
		libjavascriptcoregtk-4.0.so.18
		libjavascriptcoregtk-4.0.so.18.24.6
		libjsoncpp.so.1
		libjsoncpp.so.1.7.4
		libmanette-0.2.so.0
		libsoup-2.4.so.1
		libsoup-2.4.so.1.11.0
		libssl.so.1.1
		libwebkit2gtk-4.0.so.37
		libwebkit2gtk-4.0.so.37.68.6
		libwebp.so.6
		libwebp.so.6.0.2
		libxml2.so.2
		libxml2.so.2.9.10
	)
	local file

	dodir /opt/ecloud /opt/ecloud/compat/lib /opt/ecloud/compat/webkit2gtk-4.0/injected-bundle
	cp -a "${app_src}/." "${ED}/opt/ecloud/" || die
	rm -f "${ED}/opt/ecloud/fastplayer.log" || die

	for file in "${compat_files[@]}"; do
		cp -a "${compat_src}/${file}" "${compat_lib_dst}/" || die
	done

	cp -a "${compat_src}/webkit2gtk-4.0/WebKitNetworkProcess" "${compat_webkit_dst}/" || die
	cp -a "${compat_src}/webkit2gtk-4.0/WebKitWebProcess" "${compat_webkit_dst}/" || die
	cp -a "${compat_src}/webkit2gtk-4.0/injected-bundle/libwebkit2gtkinjectedbundle.so" \
		"${compat_webkit_dst}/injected-bundle/" || die

	patch_webkit_paths "${compat_lib_dst}/libwebkit2gtk-4.0.so.37.68.6"

	cat > "${T}/ecloud" <<-'EOF' || die
		#!/bin/sh
		export LD_LIBRARY_PATH="/opt/ecloud/compat/lib:/opt/ecloud/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
		export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
		exec /opt/ecloud/ecloud "$@"
	EOF
	dobin "${T}/ecloud"

	cat > "${T}/ecloud.desktop" <<-'EOF' || die
		[Desktop Entry]
		Name=ecloud
		Name[zh_CN]=天翼云盘
		Exec=/usr/bin/ecloud %U
		Terminal=false
		Type=Application
		Icon=ecloud
		StartupWMClass=天翼云盘
		Comment=文件云端存储 从此抛弃U盘 文件自动同步 便捷上传下载。
		MimeType=x-scheme-handler/ecloud;
		Categories=Network;
	EOF
	insinto /usr/share/applications
	newins "${T}/ecloud.desktop" ecloud.desktop

	dodir /usr/share/icons/hicolor
	cp -a "${icon_src}/." "${ED}/usr/share/icons/hicolor/" || die
}
