# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..15} )
inherit desktop optfeature pax-utils python-any-r1 toolchain-funcs unpacker xdg

MY_PN="chatgpt"
OAI_REPO="https://persistent.oaistatic.com/codex-app-prod/linux/deb"
WORKSPACE_PYTHON="cpython-3.12.15+20261001-aarch64-unknown-linux-gnu-install_only_stripped"
JXR_COMMIT="f7521879862b9085318e814c6157490dd9dbbdb4"

DESCRIPTION="OpenAI Codex desktop application for Linux"
HOMEPAGE="https://developers.openai.com/codex/app"
SRC_URI="arm64? ( workspace? (
	https://github.com/astral-sh/python-build-standalone/releases/download/20261001/${WORKSPACE_PYTHON}.tar.gz
	https://github.com/4creators/jxrlib/archive/${JXR_COMMIT}.tar.gz -> codex-jxrlib-${JXR_COMMIT}.tar.gz
) )"

S="${WORKDIR}"

LICENSE="all-rights-reserved BSD-2 MIT"
SLOT="0"
KEYWORDS=""
PROPERTIES="live"
IUSE="apparmor egl wayland +workspace"
RESTRICT="bindist mirror strip"

RDEPEND="
	app-accessibility/at-spi2-core:2
	app-arch/xz-utils
	app-crypt/tpm2-tss
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2[utils]
	dev-libs/libusb:1
	dev-libs/nspr
	dev-libs/nss
	dev-libs/openssl:0/3
	media-gfx/graphite2
	media-libs/alsa-lib
	media-libs/libcanberra-gtk3
	media-libs/libglvnd
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	virtual/libudev:=
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libdrm
	x11-libs/libnotify
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libxkbcommon
	x11-libs/libXrandr
	x11-libs/pango
	x11-misc/xdg-utils
	apparmor? ( sys-apps/apparmor )
	arm64? ( workspace? (
		app-office/libreoffice
		app-text/poppler[utils]
		dev-vcs/git
		media-libs/libheif[tools]
	) )
"

BDEPEND="
	app-arch/xz-utils
	app-crypt/gnupg
	net-misc/curl
	${PYTHON_DEPS}
"
QA_PREBUILT="*"

APP_SRCDIR="usr/lib/${MY_PN}"
APP_DESTDIR="/usr/lib/${MY_PN}"

codex_check_file() {
	local digest
	[[ -f $1 && $(stat -c %s -- "$1") == "$2" ]] || return 1
	digest=$(sha256sum -- "$1") || return 1
	[[ ${digest%% *} == "$3" ]]
}

src_unpack() {
	case ${ARCH} in
		amd64|arm64) ;;
		*) die "Unsupported architecture: ${ARCH}" ;;
	esac

	local -a curl_options=(
		--fail --location --silent --show-error
		--proto '=https' --proto-redir '=https'
		--connect-timeout 15 --retry 3 --retry-all-errors
	)
	local index_path="main/binary-${ARCH}/Packages"
	local index_hash index_size attempt
	mkdir -p -m 700 "${T}/gnupg" || die
	gpg --batch --yes --no-options --homedir "${T}/gnupg" \
		--output "${T}/openai-keyring.gpg" --dearmor \
		"${FILESDIR}/openai-linux-repository.asc" || die "Cannot load repository key"

	# Authenticate the current index rather than manifesting a mutable latest URL.
	for attempt in 1 2 3; do
		curl "${curl_options[@]}" --max-time 120 -H 'Cache-Control: no-cache' \
			-o "${T}/InRelease" "${OAI_REPO}/dists/stable/InRelease" || die "Cannot fetch signed index"
		rm -f "${T}/Release" || die
		gpgv --homedir "${T}/gnupg" --keyring "${T}/openai-keyring.gpg" \
			"${T}/InRelease" || die "Invalid repository signature"
		# gpgv verifies clearsigned files but does not export their plaintext.
		awk '
			{ sub(/\r$/, "") }
			/^-----BEGIN PGP SIGNED MESSAGE-----$/ { headers = 1; next }
			headers && /^$/ { body = 1; headers = 0; next }
			body && /^-----BEGIN PGP SIGNATURE-----$/ { exit }
			body { sub(/^- /, ""); print }
		' "${T}/InRelease" > "${T}/Release" || die
		read -r index_hash index_size < <(
			awk -v path="${index_path}" '
				{ sub(/\r$/, "") }
				/^SHA256:$/ { sha256 = 1; next }
				sha256 && /^[^[:space:]]/ { sha256 = 0 }
				sha256 && $3 == path { print $1, $2 }
			' "${T}/Release"
		)
		[[ ${index_hash} =~ ^[a-f0-9]{64}$ && ${index_size} =~ ^[1-9][0-9]*$ ]] \
			|| die "Missing signed checksum for ${ARCH}"
		curl "${curl_options[@]}" --max-time 120 -H 'Cache-Control: no-cache' \
			-o "${T}/Packages" "${OAI_REPO}/dists/stable/${index_path}" || die "Cannot fetch package index"
		codex_check_file "${T}/Packages" "${index_size}" "${index_hash}" && break
		ewarn "Repository metadata changed during download; retrying"
	done
	codex_check_file "${T}/Packages" "${index_size}" "${index_hash}" \
		|| die "Package index does not match its signed checksum"

	local record upstream_version package_size package_hash filename
	record=$(awk -v name="${MY_PN}" -v arch="${ARCH}" '
		BEGIN { RS = ""; FS = "\n" }
		{
			delete fields
			for (i = 1; i <= NF; i++) {
				sub(/\r$/, "", $i)
				separator = index($i, ": ")
				if (separator) fields[substr($i, 1, separator - 1)] = substr($i, separator + 2)
			}
			if (fields["Package"] == name && fields["Architecture"] == arch)
				print fields["Version"], fields["Size"], fields["SHA256"], fields["Filename"]
		}
	' "${T}/Packages" | sort -k1,1V | tail -n 1) || die
	read -r upstream_version package_size package_hash filename <<< "${record}"
	[[ ${upstream_version} =~ ^[0-9]+(\.[0-9]+)+(-[0-9]+)?$ &&
		${package_size} =~ ^[1-9][0-9]*$ && ${package_hash} =~ ^[a-f0-9]{64}$ &&
		${filename} == "pool/main/c/${MY_PN}/${MY_PN}_${upstream_version}_${ARCH}.deb" ]] \
		|| die "Invalid package metadata for ${ARCH}"
	einfo "Latest official Linux release: ${upstream_version} (${ARCH})"
	printf '%s\n' "${upstream_version}" > "${T}/upstream-version" || die

	local cache_dir="${PORTAGE_ACTUAL_DISTDIR:-${DISTDIR}}/${PN}-live"
	local cache_file="${cache_dir}/${MY_PN}_${upstream_version}_${ARCH}.deb"
	local download
	addwrite "${cache_dir}"
	mkdir -p "${cache_dir}" || die
	if codex_check_file "${cache_file}" "${package_size}" "${package_hash}"; then
		einfo "Using verified cached package"
	else
		download=$(mktemp "${cache_file}.XXXXXX") || die
		# Resume interrupted transfers of the immutable versioned package.
		for attempt in 1 2 3; do
			curl "${curl_options[@]}" --max-time 900 --continue-at - \
				-o "${download}" "${OAI_REPO}/${filename}" && break
		done
		if ! codex_check_file "${download}" "${package_size}" "${package_hash}"; then
			rm -f "${download}"
			die "Downloaded package does not match its signed index"
		fi
		chmod 644 "${download}" || die
		mv -fT "${download}" "${cache_file}" || die
	fi
	unpack_deb "${cache_file}"

	if [[ ${ARCH} == arm64 ]] && use workspace; then
		unpack ${A}
		"${PYTHON}" "${FILESDIR}/arm64-workspace.py" prepare \
			--resources "${WORKDIR}/${APP_SRCDIR}/resources" \
			--python "${WORKDIR}/python" --cache "${cache_dir}" \
			--output "${WORKDIR}/workspace-runtime" \
			|| die "Cannot prepare native ARM64 workspace dependencies"
	fi
}

src_prepare() {
	default
	if [[ ${ARCH} == arm64 ]] && use workspace; then
		# Keep the existing download, checksum, extraction, repair and activation
		# flow. Use the packaged runtime when upstream has no ARM64 release.
		"${PYTHON}" "${FILESDIR}/patch-workspace-installer.py" \
			"${APP_SRCDIR}/resources/app.asar" || die "Cannot patch workspace installer"
		sed -e 's/^\tar rvu/\t$(AR) rvu/' \
			-e 's/^\tranlib /\t$(RANLIB) /' \
			-e 's/$(LIBS)$/$(LIBS) $(LDFLAGS)/' \
			-i "jxrlib-${JXR_COMMIT}/Makefile" || die
		# Modern GCC requires the declaration of wcslen().
		sed -i '/^#include <limits.h>/a#include <wchar.h>' \
			"jxrlib-${JXR_COMMIT}/jxrgluelib/JXRGlueJxr.c" || die
	fi
}

src_compile() {
	if [[ ${ARCH} == arm64 ]] && use workspace; then
		emake -C "jxrlib-${JXR_COMMIT}" CC="$(tc-getCC)" \
			AR="$(tc-getAR)" RANLIB="$(tc-getRANLIB)" \
			CFLAGS="${CFLAGS} -std=gnu89 -I. -Icommon/include -Iimage/sys -D__ANSI__ -DDISABLE_PERF_MEASUREMENT" \
			LDFLAGS="${LDFLAGS}"
		"${PYTHON}" "${FILESDIR}/arm64-workspace.py" finish \
			--resources "${WORKDIR}/${APP_SRCDIR}/resources" \
			--jxr "${WORKDIR}/jxrlib-${JXR_COMMIT}" \
			--output "${WORKDIR}/workspace-runtime" \
			|| die "Cannot package native ARM64 workspace dependencies"
	fi
}

src_install() {
	dodir "${APP_DESTDIR}"
	cp -a "${APP_SRCDIR}/." "${ED}${APP_DESTDIR}/" || die
	if [[ ${ARCH} == arm64 ]] && use workspace; then
		insinto "${APP_DESTDIR}/resources/gentoo-workspace"
		doins workspace-runtime/{manifest.json,gentoo-arm64-workspace.tar.xz}
	fi

	# The Electron build uses unprivileged user namespaces and ships no
	# setuid chrome-sandbox helper.
	pax-mark m "${ED}${APP_DESTDIR}/ChatGPT"

	# Apply USE flags in the shared launcher for both desktop and CLI starts.
	# The bundled runtime ignores --ozone-platform-hint=auto and defaults to X11.
	sed -e "s|@WAYLAND@|$(usex wayland yes no)|g" \
		-e "s|@EGL@|$(usex egl yes no)|g" \
		"${FILESDIR}/codex-launcher" > "${T}/codex-launcher" || die
	exeinto "${APP_DESTDIR}"
	doexe "${T}/codex-launcher"

	dosym -r "${APP_DESTDIR}/codex-launcher" "/usr/bin/${MY_PN}"
	dosym -r "${APP_DESTDIR}/codex-launcher" "/usr/bin/${PN%-bin}"

	# Match the upstream Wayland app_id and X11 window class.
	sed "/^\[Desktop Entry\]$/a StartupWMClass=${MY_PN}" \
		"usr/share/applications/${MY_PN}.desktop" > "${T}/${MY_PN}.desktop" || die
	domenu "${T}/${MY_PN}.desktop"

	# Keep existing shortcuts working without a second application-menu entry.
	sed '/^\[Desktop Entry\]$/a NoDisplay=true' \
		"${T}/${MY_PN}.desktop" > "${T}/${PN%-bin}.desktop" || die
	domenu "${T}/${PN%-bin}.desktop"

	# The stock hicolor theme does not index a 1024x1024/apps directory.
	newicon "usr/share/pixmaps/${MY_PN}.png" "${MY_PN}.png"
	dodoc "${T}/upstream-version"

	if use apparmor; then
		insinto /etc/apparmor.d
		doins "etc/apparmor.d/${MY_PN}"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	einfo "The desktop application is available as 'chatgpt' and 'codex-desktop'."
	einfo "This preview requires unprivileged user namespaces for its renderer sandbox."
	if [[ ${ARCH} == arm64 ]] && use workspace; then
		einfo "Native ARM64 workspace dependencies are included as a Gentoo fallback."
		einfo "Restart the app, then use Settings > Workspace > Reset and install workspace."
	fi

	optfeature "repository operations from Codex" dev-vcs/git
	optfeature "system tray icon" dev-libs/libayatana-appindicator
	optfeature "audio playback" media-libs/libpulse
}
