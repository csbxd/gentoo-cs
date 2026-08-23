# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3 readme.gentoo-r1

FLUTTER_COMMIT="6655482ec06e547f90abf8ae7590466f4415978d"
FLUTTER_ENGINE_COMMIT="5d531788691ec3404cac0cee66ead4007b177363"

DESCRIPTION="Google's UI toolkit, packaged for a native Linux ARM64 host"
HOMEPAGE="https://flutter.dev/"
EGIT_REPO_URI="https://github.com/flutter/flutter.git"
EGIT_BRANCH="stable"
EGIT_COMMIT="${FLUTTER_COMMIT}"
EGIT_CLONE_TYPE="shallow"
EGIT_SUBMODULES=()

LICENSE="BSD"
SLOT="0"
KEYWORDS="-* ~arm64"
IUSE="+linux-desktop"
RESTRICT="strip"

DEPEND="acct-group/flutter"
RDEPEND="
	${DEPEND}
	~dev-lang/dart-3.13.1
	app-arch/unzip
	dev-vcs/git
	net-misc/curl
	linux-desktop? (
		dev-build/cmake
		dev-build/ninja
		llvm-core/clang
		virtual/pkgconfig
		x11-libs/gtk+:3
	)
"
BDEPEND="dev-vcs/git"

DOC_CONTENTS="The Flutter SDK is installed in /opt/flutter and uses the native
ARM64 system Dart SDK from dev-lang/dart-3.13.1.

Enable and sync the Bentoo repository before installing this package; Bentoo
provides the matching ARM64 Dart package.

Use the /usr/bin/flutter wrapper rather than invoking /opt/flutter/bin/flutter
directly. The wrapper marks the shared root-owned SDK as safe for Flutter's Git
subprocesses without changing the user's global Git configuration.

The first flutter invocation compiles flutter_tools with ARM64 Dart and
downloads Linux ARM64 engine artifacts on demand. Android SDK, NDK and Android
engine artifacts are intentionally not dependencies of this package.

Flutter writes into its own SDK tree. The tree is group-writable by the
'flutter' group. Add trusted users to that group and start a new login session:

    gpasswd -a <user> flutter

Every member of the group can modify code executed by the other members.
Manage Flutter upgrades through Portage rather than running 'flutter upgrade'."

src_prepare() {
	default
	rm -rf bin/cache || die

	# git-r3 checkouts borrow objects from DISTDIR. Make the installed clone
	# self-contained before Portage is allowed to clean the source cache.
	git checkout -B stable "${FLUTTER_COMMIT}" || die
	git repack -a -d || die
	rm -f .git/objects/info/alternates || die
	git fsck --no-dangling || die

	git remote remove origin >/dev/null 2>&1 || :
	git remote add origin "${EGIT_REPO_URI}" || die
	git update-ref refs/remotes/origin/stable "${FLUTTER_COMMIT}" || die
	git config branch.stable.remote origin || die
	git config branch.stable.merge refs/heads/stable || die
}

src_compile() {
	:
}

src_install() {
	# Keep Flutter from replacing the system Dart symlink on first launch.
	mkdir -p bin/cache || die
	printf '%s\n' "${FLUTTER_ENGINE_COMMIT}" > bin/cache/engine-dart-sdk.stamp || die

	DISABLE_AUTOFORMATTING=1 readme.gentoo_create_doc

	dodir /opt
	mv "${S}" "${ED}/opt/${PN}" || die

	fowners -R root:flutter "/opt/${PN}"
	fperms -R g+w "/opt/${PN}"
	find "${ED}/opt/${PN}" -type d -exec chmod g+s {} + || die

	dosym /usr/lib/dart "/opt/${PN}/bin/cache/dart-sdk"
	newbin "${FILESDIR}/${PN}" "${PN}"
}

pkg_postinst() {
	readme.gentoo_print_elog
}
