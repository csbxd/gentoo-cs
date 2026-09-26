# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit savedconfig toolchain-funcs

SOURCE_COMMIT=4e68e1932480960f2f4a95e80e424b34d0737dfb
CONFIG_COMMIT=35527918391e697f994d9efa02948d4308a7a766
KV_FULL=${PV}-ophub-gentoo-${PR}

DESCRIPTION="Build the ophub ARM64 kernel, modules, DTBs and module build tree from source"
HOMEPAGE="https://github.com/ophub/kernel https://github.com/ophub/linux-6.18.y"
SRC_URI="
	https://github.com/ophub/linux-6.18.y/archive/${SOURCE_COMMIT}.tar.gz -> ophub-linux-${PV}-${SOURCE_COMMIT}.tar.gz
	https://github.com/ophub/kernel/archive/${CONFIG_COMMIT}.tar.gz -> ophub-kernel-config-${CONFIG_COMMIT}.tar.gz
"
S=${WORKDIR}/linux-6.18.y-${SOURCE_COMMIT}

LICENSE="GPL-2"
SLOT="${PV}"
KEYWORDS="~arm64"
IUSE="debug test"
RESTRICT="strip !test? ( test )"

BDEPEND="
	app-alternatives/bc
	dev-lang/perl
	dev-libs/openssl
	sys-devel/bison
	sys-devel/flex
	virtual/libelf
	debug? ( dev-util/pahole )
	test? ( sys-apps/kmod )
"
RDEPEND="virtual/libelf"
IDEPEND="sys-apps/kmod"

pkg_setup() {
	# The installed Kbuild helpers must run on the target machine.
	tc-is-cross-compiler && die "This package currently supports native ARM64 builds only"
}

src_prepare() {
	default
	cp "${WORKDIR}/kernel-${CONFIG_COMMIT}/kernel-config/release/stable/config-6.18" \
		.config || die
	restore_config .config
	# Keep locally built kernels separate from ophub's published binary ABI.
	./scripts/config --set-str LOCALVERSION "-ophub-gentoo-${PR}" \
		--disable LOCALVERSION_AUTO --disable WERROR --disable GCC_PLUGINS \
		--disable MODULE_SIG --disable MODULE_COMPRESS \
		--set-str SYSTEM_TRUSTED_KEYS "" --set-str SYSTEM_REVOCATION_KEYS "" || die
	if use debug; then
		./scripts/config --disable DEBUG_INFO_NONE --enable DEBUG_INFO_DWARF5 \
			--enable DEBUG_INFO_BTF --enable DEBUG_INFO_BTF_MODULES || die
	else
		./scripts/config --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
			--disable DEBUG_INFO_DWARF4 --disable DEBUG_INFO_DWARF5 \
			--disable DEBUG_INFO_BTF --disable DEBUG_INFO_BTF_MODULES \
			--enable DEBUG_INFO_NONE || die
	fi
}

src_configure() {
	tc-export_build_env
	local ld=$(tc-getLD)
	type -P "${ld}.bfd" > /dev/null && ld+=.bfd
	MAKEARGS=(
		ARCH=arm64 CC="$(tc-getCC)" LD="${ld}"
		AR="$(tc-getAR)" NM="$(tc-getNM)" STRIP="$(tc-getSTRIP)"
		OBJCOPY="$(tc-getOBJCOPY)" OBJDUMP="$(tc-getOBJDUMP)"
		HOSTCC="$(tc-getBUILD_CC)" HOSTCXX="$(tc-getBUILD_CXX)"
		HOSTCFLAGS="${BUILD_CFLAGS}" HOSTLDFLAGS="${BUILD_LDFLAGS}"
		KBUILD_BUILD_USER=portage KBUILD_BUILD_HOST=gentoo
	)
	emake "${MAKEARGS[@]}" olddefconfig
	grep -qx 'CONFIG_MODULES=y' .config || die "CONFIG_MODULES=y is required"
	local release
	release=$(emake -s --no-print-directory "${MAKEARGS[@]}" kernelrelease) || die
	[[ ${release} == "${KV_FULL}" ]] || die "Unexpected kernel release: ${release}"
}

src_compile() {
	emake "${MAKEARGS[@]}" Image modules dtbs
}

ophub_install_headers() {
	# Use the kernel's own external-module build tree exporter, not UAPI headers.
	export OPHUB_HEADERS_DEST=$1
	emake "${MAKEARGS[@]}" run-command \
		KBUILD_RUN_COMMAND='sh scripts/package/install-extmod-build "${OPHUB_HEADERS_DEST}"'
	unset OPHUB_HEADERS_DEST
	cp -p .config System.map "$1/" || die
	if use debug; then
		cp vmlinux "$1/" || die
	fi
}

src_test() {
	local headers=${T}/headers-test
	ophub_install_headers "${headers}"
	local release
	release=$(emake -s --no-print-directory -C "${headers}" "${MAKEARGS[@]}" kernelrelease) || die
	[[ ${release} == "${KV_FULL}" ]] || die "Exported headers release mismatch"
	mkdir "${T}/module-test" || die
	cp "${FILESDIR}/module-test.c" "${T}/module-test/ophub_headers_test.c" || die
	printf '%s\n' 'obj-m += ophub_headers_test.o' > "${T}/module-test/Makefile" || die
	emake -C "${headers}" "${MAKEARGS[@]}" M="${T}/module-test" modules
	local vermagic
	vermagic=$(modinfo -F vermagic "${T}/module-test/ophub_headers_test.ko") || die
	[[ ${vermagic%% *} == "${KV_FULL}" ]] || die "External module release mismatch"
	[[ -s arch/arm64/boot/dts/rockchip/rk3399-tpm312.dtb ]] || die "Missing TPM312 DTB"
}

src_install() {
	local builddir=/usr/src/linux-${KV_FULL}
	local kerneldir=/usr/lib/ophub-kernel/${KV_FULL}
	emake "${MAKEARGS[@]}" INSTALL_MOD_PATH="${ED}" INSTALL_MOD_STRIP=1 \
		DEPMOD=true modules_install
	emake "${MAKEARGS[@]}" INSTALL_DTBS_PATH="${ED}${kerneldir}/dtbs" dtbs_install
	ophub_install_headers "${ED}${builddir}"
	rm -f "${ED}/lib/modules/${KV_FULL}/build" "${ED}/lib/modules/${KV_FULL}/source" || die
	dosym "${builddir}" "/lib/modules/${KV_FULL}/build"
	insinto "${kerneldir}"
	newins arch/arm64/boot/Image Image
	newins .config config
	doins System.map
	save_config .config
	dodoc "${FILESDIR}/README.md"
	docompress -x "${builddir}"
}

pkg_postinst() {
	depmod -b "${EROOT}/" "${KV_FULL}" || die "depmod failed"
	elog "Built kernel: ${KV_FULL}; headers: /usr/src/linux-${KV_FULL}"
	elog "Image and DTBs: /usr/lib/ophub-kernel/${KV_FULL}/"
	elog "Boot files and initramfs are managed separately; see the installed README."
	elog "Rebuild external modules with: dkms autoinstall -k ${KV_FULL}"
}
