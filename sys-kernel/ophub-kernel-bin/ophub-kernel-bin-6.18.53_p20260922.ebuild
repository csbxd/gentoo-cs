# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit toolchain-funcs

MY_PV=${PV%_p*}
KV_FULL=${MY_PV}-ophub
MY_ARCHIVE=ophub-kernel-${PV}-arm64.tar.gz

DESCRIPTION="Prebuilt ophub ARM64 kernel, modules, DTBs and matching module build tree"
HOMEPAGE="https://github.com/ophub/kernel https://github.com/unifreq/linux-6.18.y"
# This old release asset has been replaced upstream. Import the audited archive;
# never substitute another build with the same uname -r or regenerate its hash.
SRC_URI="https://github.com/ophub/kernel/releases/download/kernel_stable/${MY_PV}.tar.gz -> ${MY_ARCHIVE}"
S="${WORKDIR}/${MY_PV}"

LICENSE="GPL-2"
SLOT="${MY_PV}"
KEYWORDS="~arm64"
IUSE="test"
REQUIRED_USE="elibc_glibc"
RESTRICT="fetch mirror strip !test? ( test )"
QA_PREBUILT="*"

RDEPEND="sys-libs/glibc"
IDEPEND="sys-apps/kmod"
BDEPEND="test? ( sys-apps/kmod )"

pkg_nofetch() {
	eerror "Upstream replaces same-version release assets. This package needs the"
	eerror "original 2026-09-22 kernel_stable 6.18.53.tar.gz (122846477 bytes)."
	eerror "SHA256: 269dd8ded019f829723968a236bac40335dc9488aac8f22cf1afd5b9f3a20bb7"
	eerror "Put that archived file in your Portage DISTDIR as ${MY_ARCHIVE}"
	eerror "The current upstream download is NOT interchangeable. See README.md."
}

src_unpack() {
	unpack "${MY_ARCHIVE}"
	cd "${S}" || die
	sha256sum -c sha256sums || die "Inner archive checksum mismatch"
	local part
	for part in boot header modules dtb-rockchip dtb-amlogic dtb-allwinner; do
		mkdir "${part}" || die
		tar -xpf "${part}-${KV_FULL}.tar.gz" -C "${part}" || die
	done
}

src_prepare() {
	default
	[[ $(<header/include/config/kernel.release) == "${KV_FULL}" ]] ||
		die "Header release mismatch"
	grep -qx "#define UTS_RELEASE \"${KV_FULL}\"" header/include/generated/utsrelease.h ||
		die "Generated header release mismatch"
	local required
	for required in header/Module.symvers header/include/config/auto.conf \
		header/include/generated/autoconf.h header/scripts/basic/fixdep \
		header/scripts/mod/modpost boot/vmlinuz-${KV_FULL} boot/config-${KV_FULL} \
		boot/System.map-${KV_FULL} dtb-rockchip/rk3399-tpm312.dtb; do
		[[ -s ${required} ]] || die "Missing ${required}"
	done
	# Upstream's headers omit .config; linux-info and DKMS also need it.
	cp -p "boot/config-${KV_FULL}" header/.config || die
	cp -p "boot/System.map-${KV_FULL}" header/System.map || die
	# The publisher passed this suffix on make's command line. Preserve it for
	# kernelrelease queries as well as the already generated utsrelease.h.
	printf '%s\n' '-ophub' > header/localversion.ophub || die
	# The header archive omits DTS source trees; keep only usable include links.
	find header/scripts/dtc/include-prefixes -xtype l -delete || die
	# These files name the publisher's build host or contain depmod caches.
	rm -f "modules/${KV_FULL}/build" "modules/${KV_FULL}/source" || die
	find "modules/${KV_FULL}" -maxdepth 1 -type f -name 'modules.*' \
		! -name modules.order ! -name modules.builtin ! -name modules.builtin.modinfo \
		-delete || die
}

src_configure() { :; }
src_compile() { :; }

src_test() {
	local release
	release=$(emake -s --no-print-directory -C header ARCH=arm64 kernelrelease) || die
	[[ ${release} == "${KV_FULL}" ]] || die "Kbuild kernelrelease mismatch: ${release}"
	mkdir "${T}/module-test" || die
	cp "${FILESDIR}/module-test.c" "${T}/module-test/ophub_headers_test.c" || die
	printf '%s\n' 'obj-m += ophub_headers_test.o' > "${T}/module-test/Makefile" || die
	emake -C header ARCH=arm64 CC="$(tc-getCC)" HOSTCC="$(tc-getBUILD_CC)" \
		M="${T}/module-test" modules
	local vermagic
	vermagic=$(modinfo -F vermagic "${T}/module-test/ophub_headers_test.ko") || die
	[[ ${vermagic%% *} == "${KV_FULL}" ]] || die "Built module release mismatch"
}

src_install() {
	local builddir=/usr/src/linux-${KV_FULL}
	local kerneldir=/usr/lib/ophub-kernel/${KV_FULL}
	dodir "${builddir}" /lib/modules "${kerneldir}/dtbs"
	cp -a header/. "${ED}${builddir}/" || die
	cp -a "modules/${KV_FULL}" "${ED}/lib/modules/" || die
	dosym "${builddir}" "/lib/modules/${KV_FULL}/build"
	# This is a prepared module build tree, not a complete kernel source tree.
	insinto "${kerneldir}"
	newins "boot/vmlinuz-${KV_FULL}" Image
	newins "boot/config-${KV_FULL}" config
	newins "boot/System.map-${KV_FULL}" System.map
	local family
	for family in rockchip amlogic allwinner; do
		dodir "${kerneldir}/dtbs/${family}"
		cp -a "dtb-${family}/." "${ED}${kerneldir}/dtbs/${family}/" || die
	done
	dodoc "${FILESDIR}/README.md" "${FILESDIR}/provenance.json"
	# Portage must not compress Kbuild inputs (notably kernel Makefiles).
	docompress -x "${builddir}"
}

pkg_preinst() {
	# Adopt a manual installation only when its existing in-tree modules match.
	# A rebuild may reuse uname -r despite an ABI change; refuse that collision.
	local existing=${EROOT}/lib/modules/${KV_FULL}
	local incoming=${ED}/lib/modules/${KV_FULL}
	local file relative
	if [[ -d ${existing} ]]; then
		while IFS= read -r -d '' file; do
			relative=${file#"${incoming}/"}
			if [[ -e ${existing}/${relative} ]]; then
				cmp -s "${file}" "${existing}/${relative}" ||
					die "Different existing ${relative}; do not overwrite a same-release kernel"
			fi
		done < <(find "${incoming}" -type f -print0)
	fi
}

pkg_postinst() {
	depmod -b "${EROOT}/" "${KV_FULL}" || die "depmod failed"
	elog "Installed /usr/src/linux-${KV_FULL} and /lib/modules/${KV_FULL}/build."
	elog "Image and DTBs: /usr/lib/ophub-kernel/${KV_FULL}/"
	elog "Boot configuration and initramfs were not changed. See the installed README."
	elog "Keep this kernel slot selected while it is running or retained for rollback."
}
