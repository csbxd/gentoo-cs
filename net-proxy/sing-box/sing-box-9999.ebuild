# Copyright 2024-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

EGIT_REPO_URI="https://github.com/SagerNet/sing-box.git"
EGIT_SUBMODULES=()

inherit git-r3 go-env go-module systemd shell-completion

DESCRIPTION="The universal proxy platform"
HOMEPAGE="https://sing-box.sagernet.org/ https://github.com/SagerNet/sing-box"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS=""

# Follow: https://sing-box.sagernet.org/installation/build-from-source/#build-tags
# In upstream versions, `naive` is enabled by default, but in Gentoo's downstream versions, it is disabled by default.
IUSE="
	+quic grpc +dhcp +wireguard +utls +acme +clash-api v2ray-api
	+gvisor tor +tailscale +ccm +ocm naive +cloudflared
"

RDEPEND="
	acct-group/${PN}
	acct-user/${PN}
"

RESTRICT="network-sandbox"

S="${WORKDIR}/${P}"

src_unpack() {
	git-r3_src_unpack
	go-module_live_vendor
}

src_compile() {
	local mytags
	local version
	use quic && mytags+="with_quic,"
	use grpc && mytags+="with_grpc,"
	use dhcp && mytags+="with_dhcp,"
	use wireguard && mytags+="with_wireguard,"
	use utls && mytags+="with_utls,"
	use acme && mytags+="with_acme,"
	use clash-api && mytags+="with_clash_api,"
	use v2ray-api && mytags+="with_v2ray_api,"
	use gvisor && mytags+="with_gvisor,"
	use tor && mytags+="with_embedded_tor,"
	use tailscale && mytags+="with_tailscale,"
	use ccm && mytags+="with_ccm,"
	use ocm && mytags+="with_ocm,"
	use naive && mytags+="with_purego,with_naive_outbound,"
	use cloudflared && mytags+="with_cloudflared,"

	version="$(go run ./cmd/internal/read_tag)" || die "failed to calculate version"

	ego build -tags "${mytags%,}" \
		-gcflags=-l=4 \
		-ldflags "-X 'github.com/sagernet/sing-box/constant.Version=${version}'" \
		./cmd/sing-box

	mkdir completions || die
	./sing-box completion bash > completions/sing-box || die
	./sing-box completion fish > completions/sing-box.fish || die
	./sing-box completion zsh > completions/_sing-box || die
}

src_install() {
	if ! use naive; then
		dobin sing-box
	else
		insinto /usr/lib/sing-box
		doins sing-box "vendor/github.com/sagernet/cronet-go/lib/linux_$(go-env_goarch)/libcronet.so"
		dosym ../lib/sing-box/sing-box /usr/bin/sing-box
		fperms +x /usr/bin/sing-box /usr/lib/sing-box/sing-box
	fi

	insinto /etc/sing-box
	newins release/config/config.json config.json.example

	newinitd release/config/sing-box.initd sing-box
	systemd_dounit release/config/sing-box{,@}.service

	insinto /usr/share/dbus-1/system.d
	newins release/config/sing-box-split-dns.xml sing-box-dns.conf

	insinto /usr/share/polkit-1/rules.d
	doins release/config/sing-box.rules

	dobashcomp completions/sing-box
	dofishcomp completions/sing-box.fish
	dozshcomp completions/_sing-box
}
