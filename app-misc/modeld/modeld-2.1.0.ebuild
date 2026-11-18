# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
RUST_MIN_VER="1.88.0"

CRATES="
	atomic-waker@1.1.2
	axum-core@0.5.6
	axum@0.8.8
	bytes@1.12.1
	cfg-if@1.0.5
	displaydoc@0.2.7
	errno@0.3.15
	form_urlencoded@1.2.2
	futures-core@0.3.34
	futures-task@0.3.34
	futures-util@0.3.34
	getrandom@0.3.4
	http-body-util@0.1.5
	http-body@1.1.0
	http@1.5.0
	httparse@1.10.1
	httpdate@1.0.3
	hyper-util@0.1.21
	hyper@1.12.0
	icu_collections@2.4.0
	icu_locale_core@2.4.0
	icu_normalizer@2.4.0
	icu_normalizer_data@2.4.0
	icu_properties@2.4.0
	icu_properties_data@2.4.0
	icu_provider@2.4.0
	idna@1.1.0
	idna_adapter@1.2.2
	itoa@1.0.19
	libc@0.2.191
	litemap@0.8.3
	matchit@0.8.4
	memchr@2.8.3
	mime@0.3.18
	mio@1.2.5
	percent-encoding@2.3.2
	pin-project-lite@0.2.17
	potential_utf@0.1.6
	proc-macro2@1.0.107
	quote@1.0.47
	r-efi@5.3.0
	serde@1.0.229
	serde_core@1.0.229
	serde_derive@1.0.229
	serde_json@1.0.154
	serde_path_to_error@0.1.20
	signal-hook-registry@1.4.8
	slab@0.4.12
	smallvec@1.16.5
	socket2@0.6.5
	stable_deref_trait@1.2.1
	subtle@2.6.1
	syn@3.0.10
	sync_wrapper@1.0.2
	synstructure@0.14.0
	tinystr@0.8.5
	tokio-macros@2.7.2
	tokio@1.54.1
	tower-layer@0.3.3
	tower-service@0.3.3
	tower@0.5.3
	unicode-ident@1.0.27
	url@2.5.8
	utf8_iter@1.1.0
	utf_types@1.0.0
	wasi@0.11.1+wasi-snapshot-preview1
	wasip2@1.0.4+wasi-0.2.12
	windows-link@0.2.1
	windows-sys@0.61.2
	wit-bindgen@0.57.1
	writeable@0.6.4
	yoke-derive@0.8.4
	yoke@0.8.4
	zerofrom-derive@0.1.8
	zerofrom@0.1.8
	zerotrie@0.2.5
	zerovec-derive@0.11.7
	zerovec@0.11.9
	zmij@1.0.23
"
inherit cargo cmake systemd

DESCRIPTION="Rust GPU model scheduler and RIFE frame interpolation API"
HOMEPAGE="https://github.com/csbxd/modeld"
SRC_URI="
	https://github.com/csbxd/modeld/releases/download/v${PV}/${P}.tar.gz
	${CARGO_CRATE_URIS}
"

LICENSE="MIT Apache-2.0 BSD Unicode-3.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"
RESTRICT="!test? ( test )"

COMMON_DEPEND="
	acct-user/modeld
	dev-libs/openssl:=
	media-video/ffmpeg:=[dav1d,nvenc,openssl,zlib]
	~sci-libs/tensorrt-rtx-1.7.1.116:=
"
DEPEND="${COMMON_DEPEND}
	dev-cpp/nlohmann_json
	test? ( dev-cpp/cpp-httplib:=[ssl] )
"
RDEPEND="${COMMON_DEPEND}
	~sci-libs/modeld-rife-4.26
"
BDEPEND="virtual/pkgconfig"

src_unpack() {
	cargo_src_unpack
}

src_prepare() {
	cmake_src_prepare
}

src_configure() {
	local mycmakeargs=(
		-DMODELD_CLIENT=OFF
		-DMODELD_SERVER=ON
		-DBUILD_TESTING=$(usex test)
		-DCMAKE_CUDA_COMPILER="${EPREFIX}/opt/cuda/bin/nvcc"
		-DCMAKE_CUDA_ARCHITECTURES=89
	)
	cmake_src_configure
	export MODELD_NATIVE_LIB_DIR="${BUILD_DIR}"
	export TENSORRT_LIB_DIR="${EPREFIX}/opt/tensorrt-rtx/lib"
	export CUDA_LIB_DIR="${EPREFIX}/opt/cuda/lib64"
	cargo_src_configure --frozen
}

src_compile() {
	cmake_src_compile
	export MODELD_NATIVE_LIB_DIR="${BUILD_DIR}"
	export TENSORRT_LIB_DIR="${EPREFIX}/opt/tensorrt-rtx/lib"
	export CUDA_LIB_DIR="${EPREFIX}/opt/cuda/lib64"
	cargo_src_compile
}

src_test() {
	cmake_src_test
	export MODELD_NATIVE_LIB_DIR="${BUILD_DIR}"
	export TENSORRT_LIB_DIR="${EPREFIX}/opt/tensorrt-rtx/lib"
	export CUDA_LIB_DIR="${EPREFIX}/opt/cuda/lib64"
	cargo_src_test
}

src_install() {
	cargo_src_install --path server
	insinto /etc/modeld
	newins config/server.example.json server.json
	fperms 0640 /etc/modeld/server.json
	fowners root:modeld /etc/modeld
	fowners root:modeld /etc/modeld/server.json
	newinitd packaging/modeld.initd modeld
	systemd_dounit packaging/modeld.service
	dodoc README.md
	docinto docs
	dodoc docs/api.md docs/architecture.md docs/validation-2.1.0-browser.json
}

pkg_postinst() {
	if [[ ! -e "${EROOT}/etc/modeld/api.token" ]]; then
		( umask 077; openssl rand -hex 32 > "${EROOT}/etc/modeld/api.token" ) ||
			die "API token generation failed"
		chown root:modeld "${EROOT}/etc/modeld/api.token" || die
		chmod 0640 "${EROOT}/etc/modeld/api.token" || die
	fi
	elog "Configure the 2.0 server.json listen address and inference/limits/output sections."
	elog "Enable modeld with systemd or OpenRC. API credentials are in /etc/modeld/api.token."
	elog "Only frame interpolation is implemented. The inference profile is native FP32 with TF32 disabled."
	elog "2.0 requires matching clients and the strict configuration; API: /api/v2, health: /healthz."
}
