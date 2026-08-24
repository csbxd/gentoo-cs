#!/bin/sh

if [ "${XDG_SESSION_TYPE-}" = wayland ]; then
	unset WAYLAND_DISPLAY
	export WEMEET_XWAYLAND=1
fi

export XDG_SESSION_TYPE=x11
export QT_QPA_PLATFORM=xcb
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export QT_STYLE_OVERRIDE=fusion
export IBUS_USE_PORTAL=1

fontconfig_dir="${HOME}/.config/fontconfig"
mkdir -p "${fontconfig_dir}"

case "${LANG-} ${LC_ALL-} ${LANGUAGE-}" in
	*zh*) export LC_ALL=zh_CN.UTF-8 ;;
	*) export LC_ALL=en_US.UTF-8 ;;
esac

if [ -x /usr/bin/pipewire-pulse ]; then
	export PULSE_LATENCY_MSEC=20
fi

if [ -e /dev/nvidia0 ]; then
	export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
fi

compat_dir=/opt/wemeet/qt5-webengine-16k
page_size=$(getconf PAGESIZE 2>/dev/null || echo 4096)

if [ "$(uname -m)" = aarch64 ] && [ "${page_size}" -gt 4096 ]; then
	if [ ! -x /usr/bin/bwrap ]; then
		echo "wemeet: bubblewrap is required for the ARM64 16K WebEngine compatibility layer" >&2
		exit 1
	fi

	export LD_LIBRARY_PATH="${compat_dir}/lib:/opt/wemeet/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
	export QTWEBENGINEPROCESS_PATH="${compat_dir}/libexec/QtWebEngineProcess"
	export QTWEBENGINE_DISABLE_SANDBOX=1
	export QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --disable-gpu --disable-gpu-compositing"

	exec bwrap --dev-bind / / \
		--ro-bind "${compat_dir}/resources" /opt/wemeet/resources \
		--ro-bind "${compat_dir}/translations/qtwebengine_locales" \
			/opt/wemeet/translations/qtwebengine_locales \
		/opt/wemeet/bin/wemeetapp "$@"
fi

if [ -x /usr/bin/bwrap ]; then
	exec bwrap --dev-bind / / \
		--tmpfs "${HOME}/.config" \
		--ro-bind "${fontconfig_dir}" "${fontconfig_dir}" \
		/opt/wemeet/bin/wemeetapp "$@"
fi

exec /opt/wemeet/bin/wemeetapp "$@"
