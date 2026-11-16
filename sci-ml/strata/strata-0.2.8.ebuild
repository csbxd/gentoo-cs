# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )
CMAKE_BUILD_TYPE=Release
inherit cmake cuda python-single-r1 systemd toolchain-funcs

STRATA_COMMIT=870aedd9e1ebe1c91f94da93b59af17729f6c5c0
LLAMA_COMMIT=3cf03257f219afbe7334045ff7c6a06ac68c627d

DESCRIPTION="CPU/CUDA expert-tiered MoE inference engine and compatible API server"
HOMEPAGE="https://github.com/Niko1221/Strata"
SRC_URI="
	https://github.com/Niko1221/Strata/archive/${STRATA_COMMIT}.tar.gz -> ${P}.tar.gz
	https://github.com/ggml-org/llama.cpp/archive/${LLAMA_COMMIT}.tar.gz -> strata-llama-${LLAMA_COMMIT}.tar.gz
"
S="${WORKDIR}/Strata-${STRATA_COMMIT}"

LICENSE="MIT OFL-1.1"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd test +vision"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"
RESTRICT="!test? ( test )"

PYDEPS="$(python_gen_cond_dep '
	dev-python/jinja2[${PYTHON_USEDEP}]
	dev-python/numpy[${PYTHON_USEDEP}]
	dev-python/pillow[${PYTHON_USEDEP}]
	dev-python/psutil[${PYTHON_USEDEP}]
	dev-python/pyyaml[${PYTHON_USEDEP}]
	dev-python/regex[${PYTHON_USEDEP}]
	dev-python/requests[${PYTHON_USEDEP}]
	dev-python/tqdm[${PYTHON_USEDEP}]
	dev-python/truststore[${PYTHON_USEDEP}]
')"
RDEPEND="
	${PYTHON_DEPS}
	${PYDEPS}
	>=dev-util/nvidia-cuda-toolkit-12.8
	systemd? ( acct-user/strata )
"
DEPEND=">=dev-util/nvidia-cuda-toolkit-12.8"
BDEPEND="${PYTHON_DEPS} test? ( ${PYDEPS} )"

PATCHES=(
	"${FILESDIR}/${PN}-0.2.8-projection-models.patch"
	"${FILESDIR}/${PN}-0.2.8-web-projection-default-off.patch"
)

pkg_setup() {
	python-single-r1_pkg_setup
	if [[ -z ${CUDAARCHS} ]]; then
		ewarn "CUDAARCHS is unset; building for the NVIDIA GPU visible to CMake."
		ewarn "Set CUDAARCHS in package.env for reproducible builds, e.g. 89-real."
	fi
}

src_prepare() {
	cmake_src_prepare
	python_fix_shebang tools serve strata_cli strata_control
}

src_configure() {
	local mycmakeargs=(
		-DSTRATA_ENABLE_CUDA=ON
		-DSTRATA_PORTABLE=OFF
		-DSTRATA_BUILD_TESTS=OFF
		-DSTRATA_NATIVE_EXPERTS=ON
		-DSTRATA_Q6K_EXPERTS=ON
		-DSTRATA_MMQ_KQUANTS=ON
		-DSTRATA_GGML_DIR="${WORKDIR}/llama.cpp-${LLAMA_COMMIT}"
		-DCMAKE_CUDA_COMPILER="${EPREFIX}/opt/cuda/bin/nvcc"
		-DCMAKE_CUDA_HOST_COMPILER="$(tc-getCXX)"
		-DCUDAToolkit_ROOT="${EPREFIX}/opt/cuda"
		-DCMAKE_CUDA_ARCHITECTURES="${CUDAARCHS:-native}"
		-DCMAKE_CUDA_FLAGS="${NVCCFLAGS:--O3} -Xcompiler=${CXXFLAGS// /,}"
	)
	local BUILD_DIR="${WORKDIR}/engine-build"
	cmake_src_configure

	if use vision; then
		local CMAKE_USE_DIR="${S}/tools/vision"
		BUILD_DIR="${WORKDIR}/vision-build"
		mycmakeargs=(
			-DLLAMA_DIR="${WORKDIR}/llama.cpp-${LLAMA_COMMIT}"
			-DSTRATA_PORTABLE=OFF
			-DSTRATA_VISION_CUDA=OFF
		)
		cmake_src_configure
	fi
}

src_compile() {
	local BUILD_DIR="${WORKDIR}/engine-build"
	cmake_src_compile strata
	if use vision; then
		BUILD_DIR="${WORKDIR}/vision-build"
		cmake_src_compile strata-vision
	fi

	CUDAARCHS="${CUDAARCHS:-native}" "${PYTHON}" - <<'PY' || die
import json, os
import setup
record = {
	"source": "local", "version": setup.source_version(),
	"archs": os.environ["CUDAARCHS"].split(";"),
	"vision": "cpu" if os.path.isfile("../vision-build/bin/strata-vision") else "none",
	"src": setup.source_hash(setup.ENGINE_SOURCES),
	"vision_src": setup.source_hash(setup.VISION_SOURCES),
	"dependency_source": "Gentoo ebuilds",
}
with open("BUILD.json", "w") as f:
	json.dump(record, f, indent=2)
	f.write("\n")
PY
}

src_test() {
	"${PYTHON}" -m unittest discover -s tests/terminal \
		-p test_projection_model_alias.py -v || die "Projection model tests failed"
}

src_install() {
	insinto /opt/strata
	doins -r serve strata_cli strata_control tools cmake src include
	doins strata.py setup.py chat.py highlight.py CMakeLists.txt requirements.txt BUILD.json LICENSE
	insinto /opt/strata/third_party
	doins -r third_party/ggml
	insinto /opt/strata/third_party/llama.cpp/gguf-py
	doins -r "${WORKDIR}/llama.cpp-${LLAMA_COMMIT}/gguf-py/gguf"
	insinto /opt/strata/third_party/llama.cpp
	doins "${WORKDIR}/llama.cpp-${LLAMA_COMMIT}/LICENSE"
	insinto /usr/share/strata
	doins -r data
	dosym ../../var/lib/strata/data /opt/strata/data
	exeinto /opt/strata/engine
	doexe "${WORKDIR}/engine-build/strata"
	doexe "${WORKDIR}/engine-build/libstrata_kq.so"
	use vision && doexe "${WORKDIR}/vision-build/bin/strata-vision"

	newbin "${FILESDIR}/strata-launcher" strata
	sed -i -e "s|@PYTHON@|${PYTHON}|g" -e "s|@PREFIX@|${EPREFIX}|g" \
		"${ED}/usr/bin/strata" || die
	python_optimize "${ED}/opt/strata"

	insinto /etc/strata
	doins "${FILESDIR}/server.example.json"
	keepdir /var/lib/strata/data /var/log/strata
	if use systemd; then
		sed -e "s|@PYTHON@|${PYTHON}|g" -e "s|@PREFIX@|${EPREFIX}|g" \
			"${FILESDIR}/strata.service" > "${T}/strata.service" || die
		systemd_dounit "${T}/strata.service"
		fowners strata:strata /etc/strata /var/lib/strata /var/log/strata
		fperms 0750 /etc/strata /var/log/strata
	fi
	dodoc README.md docs/API_PROJECTION_MODELS.md
}

pkg_postinst() {
	einfo "Model weights are not downloaded by this package."
	einfo "Data: /var/lib/strata/data; bundled small profiles: /usr/share/strata/data."
	einfo "Copy /etc/strata/server.example.json to server.json and edit it before starting."
	einfo "Use emerge to update this installation; see docs/strata.md in gentoo-cs."
}
