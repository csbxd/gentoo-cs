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
# Flutter's frontend server and gen_snapshot exchange Kernel binaries. Patch
# releases in the Dart 3.13 line use the same binary format; adjacent minor
# releases do not, so keep the system SDK on the engine's minor release.
RDEPEND="
	${DEPEND}
	>=dev-lang/dart-3.13.0
	<dev-lang/dart-3.14.0
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

PATCHES=(
	"${FILESDIR}/${PN}-3.47.1-arm64-android-cache.patch"
)

DOC_CONTENTS="The Flutter SDK is installed in /opt/flutter and uses a native
ARM64 system Dart SDK from the 3.13 release series. Flutter 3.47.1 was released
with Dart 3.13.1, while its source packages support compatible Dart 3.13 patch
releases.

Enable and sync the Bentoo repository to provide the native ARM64 Dart SDK.

Use the /usr/bin/flutter wrapper rather than invoking /opt/flutter/bin/flutter
directly. The wrapper marks the shared root-owned SDK as safe for Flutter's Git
subprocesses without changing the user's global Git configuration.

On Linux ARM64, the wrapper also redirects Flutter's Gradle subprocess to
~/Android/Sdk/build-tools/36.1.0/aapt2 when that native binary exists. The
override is scoped to the current Flutter command; no Gradle configuration or
extra command-line parameter is required.

The first flutter invocation compiles flutter_tools with ARM64 Dart and
downloads Linux ARM64 engine artifacts on demand. Android SDK, NDK and Android
engine artifacts are intentionally not dependencies of this package.

The wrapper removes an unused x86-64 frontend snapshot mistakenly bundled in
Flutter 3.47.1's Linux ARM64 engine archive after each invocation.

On Linux ARM64, Flutter's cache is restricted to Android ARM64 target artifacts
and locally supplied native Android gen_snapshot binaries. It never downloads
the upstream Linux x64 Android host tools.

Flutter writes into its own SDK tree. The tree is group-writable by the
'flutter' group. Add trusted users to that group and start a new login session:

    gpasswd -a <user> flutter

Every member of the group can modify code executed by the other members.
Manage Flutter upgrades through Portage rather than running 'flutter upgrade'."

src_prepare() {
	default
	rm -rf bin/cache || die

	# git-r3 checkouts borrow objects from DISTDIR. Make the installed clone
	# self-contained before Portage is allowed to clean the source cache. Keep
	# only the pinned snapshot instead of copying the complete stable history.
	git checkout -B stable "${FLUTTER_COMMIT}" || die
	local ref
	while read -r ref; do
		[[ ${ref} == refs/heads/stable ]] || git update-ref -d "${ref}" || die
	done < <(git for-each-ref --format='%(refname)')
	printf '%s\n' "${FLUTTER_COMMIT}" > .git/shallow || die
	git reflog expire --expire=now --all || die
	git repack -a -d || die
	rm -f .git/objects/info/alternates || die
	git prune-packed || die
	git fsck --no-dangling || die

	git remote remove origin >/dev/null 2>&1 || :
	git remote add origin "${EGIT_REPO_URI}" || die
	git update-ref refs/remotes/origin/stable "${FLUTTER_COMMIT}" || die
	git update-ref "refs/tags/${PV}" "${FLUTTER_COMMIT}" || die
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
