# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

EGIT_REPO_URI="https://github.com/multica-ai/multica.git"
EGIT_CHECKOUT_DIR="${WORKDIR}/${P}"

inherit git-r3 go-module

DESCRIPTION="Local agent runtime and management CLI for the Multica platform"
HOMEPAGE="https://multica.ai https://github.com/multica-ai/multica"

LICENSE="Multica"
SLOT="0"
KEYWORDS=""

RESTRICT="network-sandbox"

BDEPEND+="
	>=dev-lang/go-1.26.1:=
"

S="${EGIT_CHECKOUT_DIR}/server"

src_unpack() {
	git-r3_src_unpack
	go-module_live_vendor
}

src_compile() {
	local version commit date

	version="$(git describe --tags --always --dirty 2>/dev/null || echo dev)"
	commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
	date="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

	CGO_ENABLED=0 ego build -v -trimpath \
		-ldflags "-X main.version=${version} -X main.commit=${commit} -X main.date=${date}" \
		-o multica ./cmd/multica
}

src_install() {
	dobin multica

	dodoc \
		"${EGIT_CHECKOUT_DIR}"/README.md \
		"${EGIT_CHECKOUT_DIR}"/README.zh-CN.md \
		"${EGIT_CHECKOUT_DIR}"/CLI_INSTALL.md \
		"${EGIT_CHECKOUT_DIR}"/CLI_AND_DAEMON.md \
		"${EGIT_CHECKOUT_DIR}"/LICENSE
}
