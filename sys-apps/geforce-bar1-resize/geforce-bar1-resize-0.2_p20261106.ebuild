# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )
inherit python-single-r1 systemd udev

DESCRIPTION="Volatile GeForce BAR1 resizing before the NVIDIA driver binds"
HOMEPAGE="https://github.com/noon-at-cgn/geforce-bar1-resize"
COMMIT="53466608917ff5d8c660eefcee7c7e6c4261ef1b"
SRC_URI="https://github.com/noon-at-cgn/${PN}/archive/${COMMIT}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${PN}-${COMMIT}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd +verify"
REQUIRED_USE="verify? ( ${PYTHON_REQUIRED_USE} )"

RDEPEND="
	>=app-shells/bash-4
	sys-apps/pciutils
	sys-apps/kmod
	systemd? ( sys-apps/systemd )
	verify? (
		${PYTHON_DEPS}
		dev-util/vulkan-tools
		media-libs/vulkan-loader
		sys-devel/gcc
	)
"

PATCHES=( "${FILESDIR}/${PN}-0.2-gentoo-paths.patch" )

pkg_setup() {
	if use verify; then
		python-single-r1_pkg_setup
	fi
}

src_install() {
	dosbin scripts/geforce-bar1-resize
	if use systemd; then
		systemd_dounit systemd/geforce-bar1-resize{,-record@}.service
		udev_dorules udev/90-geforce-bar1-resize.rules
	fi
	insinto /usr/share/${PN}
	doins config/geforce-bar1-resize.conf.example
	if use verify; then
		python_fix_shebang verify/{bar1_report,cuda_memcheck,vk_bar_verify,vk_heaps}.py
		doins -r verify
	fi
	dodoc README.md
	dodoc -r docs
}

pkg_postinst() {
	use systemd && udev_reload
	elog "Review /usr/share/${PN}/geforce-bar1-resize.conf.example."
	elog "The service is not enabled automatically. Select explicit PCI devices"
	elog "in /etc/geforce-bar1-resize.conf before enabling it."
}

pkg_postrm() {
	if use systemd; then
		udev_reload
	fi
}
