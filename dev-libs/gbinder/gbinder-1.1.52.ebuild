# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit toolchain-funcs

DESCRIPTION="GLib-style interface to binder"
HOMEPAGE="https://github.com/mer-hybris/libgbinder"

MY_PN="lib${PN}"
MY_P="${MY_PN}-${PV}"
SRC_URI="https://github.com/mer-hybris/libgbinder/archive/${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${MY_P}"

LICENSE="BSD"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64 ~x86"

DEPEND="
	dev-libs/glib
	dev-libs/libglibutil
"
RDEPEND="${DEPEND}"
BDEPEND="
	sys-apps/sed
	virtual/pkgconfig
"

PATCHES=(
	"${FILESDIR}/gbinder-1.1.52-respect-env.patch"
)

src_prepare() {
	sed -i -e "s|ranlib|$(tc-getRANLIB)|" Makefile || die
	default
}

src_compile() {
	emake LIBDIR="${EPREFIX}/usr/$(get_libdir)"
}

src_install() {
	emake LIBDIR="${EPREFIX}/usr/$(get_libdir)" \
		DESTDIR="${D}" \
		INSTALL_INCLUDE_DIR="${ED}/usr/include/gbinder" \
		install-dev
}
