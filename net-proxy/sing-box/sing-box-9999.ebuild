# Copyright 2024-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3 go-module systemd shell-completion

DESCRIPTION="The universal proxy platform (dev-next branch)"
HOMEPAGE="https://sing-box.sagernet.org/ https://github.com/SagerNet/sing-box"
EGIT_REPO_URI="https://github.com/SagerNet/sing-box.git"
EGIT_BRANCH="dev-next"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS=""
IUSE="+quic grpc +dhcp +wireguard +utls +acme +clash-api v2ray-api gvisor tor tailscale"

DEPEND="${RDEPEND}"

src_unpack() {
	git-r3_src_unpack
	go-module_live_vendor
}

src_compile() {
	local mytags=(
		$(usex quic 'with_quic' '')
		$(usex grpc 'with_grpc' '')
		$(usex dhcp 'with_dhcp' '')
		$(usex wireguard 'with_wireguard' '')
		$(usex utls 'with_utls' '')
		$(usex acme 'with_acme' '')
		$(usex clash-api 'with_clash_api' '')
		$(usex v2ray-api 'with_v2ray_api' '')
		$(usex gvisor 'with_gvisor' '')
		$(usex tor 'with_embedded_tor' '')
		$(usex tailscale 'with_tailscale' '')
	)

	# 过滤空值并转换为逗号分隔的标签
	mytags=$(printf "%s," ${mytags[@]} | sed 's/,,*$//')

	local VERSION
	VERSION=$(go run ./cmd/internal/read_tag -nightly) || die "Failed to read version tag"

	ego build -o sing-box -trimpath -tags "${mytags}" \
		-ldflags "-s -w -X 'github.com/sagernet/sing-box/constant.Version=${VERSION}'" \
		./cmd/sing-box

	mkdir -v completions

	./sing-box completion bash > completions/sing-box
	./sing-box completion fish > completions/sing-box.fish
	./sing-box completion zsh > completions/_sing-box
}

src_install() {
	sed -i '/^User=sing-box$/d; /^StateDirectory=sing-box$/d' release/config/sing-box.service
	sed -i '/^User=sing-box$/d; /^StateDirectory=sing-box$/d' release/config/sing-box@.service

	dobin sing-box
	insinto /etc/sing-box
	newins release/config/config.json config.json.example
	systemd_dounit release/config/sing-box{,@}.service
	dobashcomp completions/sing-box
	dofishcomp completions/sing-box.fish
	dozshcomp completions/_sing-box
}
