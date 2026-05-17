# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Asahi-tuned Waydroid images for 16 KiB page-size systems"
HOMEPAGE="
	https://waydro.id
	https://github.com/csbxd/gentoo-cs
	https://github.com/yuk1n0w/waydroid-on-asahi
	https://github.com/UtkarshVerma/waydroid-on-asahi
"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~arm64"
RESTRICT="mirror network-sandbox"

RDEPEND="
	app-containers/waydroid
	!app-containers/waydroid-images
"
BDEPEND="
	net-misc/curl
"

S="${WORKDIR}"

waydroid_asahi_release_base() {
	if [[ -n ${WAYDROID_ASAHI_RELEASE_BASE} ]]; then
		printf '%s\n' "${WAYDROID_ASAHI_RELEASE_BASE%/}"
	else
		printf '%s\n' "https://github.com/yuk1n0w/waydroid-on-asahi/releases/download/LineageOS-23"
	fi
}

waydroid_asahi_fetch() {
	local url=$1
	local output=$2

	curl --retry 3 -fL "${url}" -o "${output}" || die "Failed to download ${url}"
}

pkg_pretend() {
	local page_size

	[[ ${ARCH} == arm64 ]] || die "${PN} only supports ARCH=arm64"

	page_size=$(getconf PAGE_SIZE 2>/dev/null) || die "Unable to determine host page size"
	[[ ${page_size} == 16384 ]] || die "${PN} requires a 16 KiB page-size host, got ${page_size}"
}

src_unpack() {
	local release_base sums_url system_url vendor_url sums_file expected

	release_base=$(waydroid_asahi_release_base)
	sums_url="${WAYDROID_ASAHI_SHA256SUMS_URL:-${release_base}/SHA256SUMS}"
	system_url="${WAYDROID_ASAHI_SYSTEM_URL:-${release_base}/system.img}"
	vendor_url="${WAYDROID_ASAHI_VENDOR_URL:-${release_base}/vendor.img}"

	if [[ ${WAYDROID_ASAHI_SKIP_SUMCHECK:-0} != 1 ]]; then
		sums_file="${T}/SHA256SUMS"
		waydroid_asahi_fetch "${sums_url}" "${sums_file}"
	fi

	waydroid_asahi_fetch "${system_url}" "${WORKDIR}/system.img"
	waydroid_asahi_fetch "${vendor_url}" "${WORKDIR}/vendor.img"

	if [[ ${WAYDROID_ASAHI_SKIP_SUMCHECK:-0} != 1 ]]; then
		expected=$(awk '$2 == "system.img" { print $1 }' "${sums_file}")
		[[ -n ${expected} ]] || die "system.img checksum missing from ${sums_url}"
		printf '%s  %s\n' "${expected}" "${WORKDIR}/system.img" | sha256sum -c - >/dev/null || die "system.img checksum mismatch"

		expected=$(awk '$2 == "vendor.img" { print $1 }' "${sums_file}")
		[[ -n ${expected} ]] || die "vendor.img checksum missing from ${sums_url}"
		printf '%s  %s\n' "${expected}" "${WORKDIR}/vendor.img" | sha256sum -c - >/dev/null || die "vendor.img checksum mismatch"
	fi
}

src_install() {
	insinto /usr/share/waydroid-extra/images
	doins "${WORKDIR}/system.img" "${WORKDIR}/vendor.img"
}

pkg_postinst() {
	elog "Installed Asahi-tuned Waydroid images to /usr/share/waydroid-extra/images."
	elog "Run 'waydroid init -f' to switch Waydroid to these images."
	elog "Override the upstream asset location with WAYDROID_ASAHI_RELEASE_BASE if needed."
	ewarn "Known limitation: camera support is disabled in this build."
}
