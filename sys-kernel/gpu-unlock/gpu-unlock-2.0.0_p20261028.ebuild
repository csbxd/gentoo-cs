# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MODULES_INITRAMFS_IUSE=+initramfs
MODULES_KERNEL_MIN=6.18
PYTHON_COMPAT=( python3_{12..15} )
inherit linux-mod-r1 python-any-r1 toolchain-funcs

COMMIT=7eb51bccae0a0b7e599e084d971170e9a1e82d0c
NV=610.43.03
DESCRIPTION="Opt-in pre-driver GeForce tensor throughput unlock"
HOMEPAGE="https://github.com/Zagitta/gpu-unlock"
SRC_URI="
	https://github.com/Zagitta/${PN}/archive/${COMMIT}.tar.gz -> ${P}.tar.gz
	https://download.nvidia.com/XFree86/NVIDIA-kernel-module-source/NVIDIA-kernel-module-source-${NV}.tar.xz
	https://download.nvidia.com/XFree86/Linux-x86_64/${NV}/NVIDIA-Linux-x86_64-${NV}-no-compat32.run
"
S="${WORKDIR}/${PN}-${COMMIT}"

LICENSE="GPL-2 MIT NVIDIA-2025"
SLOT="0"
KEYWORDS="~amd64"
IUSE="bench"
RESTRICT="bindist mirror"
BDEPEND+="
	${PYTHON_DEPS}
	app-arch/zstd
	bench? ( >=dev-util/nvidia-cuda-toolkit-12.8 )
"
RDEPEND+=" bench? ( >=dev-util/nvidia-cuda-toolkit-12.8 )"

src_unpack() {
	unpack "${P}.tar.gz" "NVIDIA-kernel-module-source-${NV}.tar.xz"
}

pkg_setup() {
	linux-mod-r1_pkg_setup
	python-any-r1_pkg_setup
}

src_compile() {
	"${PYTHON}" firmware/extract_gsp.py \
		"${DISTDIR}/NVIDIA-Linux-x86_64-${NV}-no-compat32.run" "${WORKDIR}/assets" || die
	"${PYTHON}" firmware/extract_boot_assets.py \
		"${WORKDIR}/NVIDIA-kernel-module-source-${NV}" "${WORKDIR}/assets" || die
	local modlist=( gpu_unlock=extra:kernel/gpu_unlock )
	local modargs=( KDIR="${KV_OUT_DIR}" )
	linux-mod-r1_src_compile
	if use bench; then
		"${EPREFIX}/opt/cuda/bin/nvcc" -O3 -DNDEBUG \
			-ccbin "$(tc-getCXX)" -arch="sm_${GPU_UNLOCK_BENCH_ARCH:-89}" \
			-Xcompiler=-O3 -Xcompiler=-march=native \
			"${FILESDIR}/tensor-bench.cu" -lcublas -o tensor-bench || die
	fi
}

src_install() {
	linux-mod-r1_src_install
	insinto /lib/firmware/gpu-unlock/${NV}
	doins "${WORKDIR}/assets/"*.bin
	if use initramfs; then
		insinto /usr/lib/dracut/dracut.conf.d
		newins packaging/boot/dracut.conf 20-gpu-unlock-force.conf
	fi
	if use bench; then
		exeinto /usr/libexec/gpu-unlock
		doexe tensor-bench
		insinto /usr/share/gpu-unlock/bench
		doins "${FILESDIR}/"{tensor-bench.cu,run-matrix.py,strata-compare.py}
	fi
	docinto licenses
	dodoc licenses/*.txt "${WORKDIR}/assets/NVIDIA-LICENSE" firmware/NOTICE.md
}

pkg_postinst() {
	linux-mod-r1_pkg_postinst
	elog "The module is inactive unless the kernel command line opts in."
	elog "Select a reviewed PCI device: gpu_unlock.targets=0000:41:00.0 (example)."
	elog "Load it from the initramfs, before NVIDIA binds. Ada support is experimental."
	elog "The NVIDIA 610 input only supplies firmware; your installed driver is unchanged."
}
