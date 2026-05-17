#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: build-waydroid-asahi-images.sh --android-top DIR --out-dir DIR --patch-file FILE [options]

Required arguments:
  --android-top DIR      Persistent Android checkout/build directory
  --out-dir DIR          Destination directory for system.img and vendor.img
  --patch-file FILE      Patch file to apply after apply-waydroid-patches

Optional arguments:
  --jobs N               Parallel jobs for repo sync and make (default: nproc)
  --ccache-dir DIR       ccache directory (default: DIR/ccache under android-top)
  --lineage-branch REF   LineageOS branch (default: lineage-23.0)
  --vendor-repo REPO     WayDroid vendor repo (default: WayDroid-ATV/android_vendor_waydroid)
  --vendor-ref REF       WayDroid vendor ref (default: lineage-23.0)
  --gapps                Build the GApps variant instead of vanilla
  --no-repo-verify       Disable repo's GPG verification during repo init
  --skip-sync            Skip both repo sync phases
  --skip-lfs             Skip git-lfs pulls
EOF
}

require_cmd() {
	local cmd

	for cmd in "$@"; do
		command -v "${cmd}" >/dev/null 2>&1 || {
			printf 'Missing required command: %s\n' "${cmd}" >&2
			exit 1
		}
	done
}

apply_patch_if_needed() {
	local android_top=$1
	local patch_file=$2

	if patch --dry-run -Np1 -d "${android_top}" < "${patch_file}" >/dev/null 2>&1; then
		patch -Np1 -d "${android_top}" < "${patch_file}"
		return
	fi

	if patch --dry-run -R -Np1 -d "${android_top}" < "${patch_file}" >/dev/null 2>&1; then
		printf 'Asahi patch already applied, continuing.\n'
		return
	fi

	printf 'Unable to apply %s cleanly.\n' "${patch_file}" >&2
	exit 1
}

detect_product_out() {
	local android_top=$1
	local product_out="${android_top}/out/target/product/waydroid_arm64_only"

	if [[ -d ${product_out} ]]; then
		printf '%s\n' "${product_out}"
		return
	fi

	product_out=$(find "${android_top}/out/target/product" -maxdepth 2 -type f -name system.img -printf '%h\n' | head -n1)
	[[ -n ${product_out} ]] || {
		printf 'Unable to locate built images under %s/out/target/product\n' "${android_top}" >&2
		exit 1
	}
	printf '%s\n' "${product_out}"
}

ANDROID_TOP=
OUT_DIR=
PATCH_FILE=
JOBS=$(nproc 2>/dev/null || echo 1)
CCACHE_DIR=
LINEAGE_BRANCH=lineage-23.0
VENDOR_REPO=WayDroid-ATV/android_vendor_waydroid
VENDOR_REF=lineage-23.0
BUILD_GAPPS=0
NO_REPO_VERIFY=0
SKIP_SYNC=0
SKIP_LFS=0

while [[ $# -gt 0 ]]; do
	case $1 in
		--android-top)
			ANDROID_TOP=$2
			shift 2
			;;
		--out-dir)
			OUT_DIR=$2
			shift 2
			;;
		--patch-file)
			PATCH_FILE=$2
			shift 2
			;;
		--jobs)
			JOBS=$2
			shift 2
			;;
		--ccache-dir)
			CCACHE_DIR=$2
			shift 2
			;;
		--lineage-branch)
			LINEAGE_BRANCH=$2
			shift 2
			;;
		--vendor-repo)
			VENDOR_REPO=$2
			shift 2
			;;
		--vendor-ref)
			VENDOR_REF=$2
			shift 2
			;;
		--gapps)
			BUILD_GAPPS=1
			shift
			;;
		--no-repo-verify)
			NO_REPO_VERIFY=1
			shift
			;;
		--skip-sync)
			SKIP_SYNC=1
			shift
			;;
		--skip-lfs)
			SKIP_LFS=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			printf 'Unknown argument: %s\n' "$1" >&2
			usage >&2
			exit 1
			;;
	esac
done

[[ -n ${ANDROID_TOP} && -n ${OUT_DIR} && -n ${PATCH_FILE} ]] || {
	usage >&2
	exit 1
}

require_cmd bash ccache curl git git-lfs make patch repo sha256sum

mkdir -p "${ANDROID_TOP}" "${OUT_DIR}"
[[ -n ${CCACHE_DIR} ]] || CCACHE_DIR="${ANDROID_TOP}/ccache"
mkdir -p "${CCACHE_DIR}"

if [[ ! -d ${ANDROID_TOP}/.repo ]]; then
	(
		cd "${ANDROID_TOP}"
		repo_init_args=(
			-u "https://github.com/LineageOS/android.git"
			-b "${LINEAGE_BRANCH}"
			--git-lfs
			--no-clone-bundle
		)
		if [[ ${NO_REPO_VERIFY} -eq 1 ]]; then
			repo_init_args+=( --no-repo-verify )
		fi
		repo init "${repo_init_args[@]}"
	)
fi

cd "${ANDROID_TOP}"

if [[ ${SKIP_SYNC} -eq 0 ]]; then
	repo sync -j"${JOBS}" build/make
fi

tmp_manifest_script=$(mktemp)
trap 'rm -f "${tmp_manifest_script}"' EXIT
curl --retry 3 -fsSL \
	--retry-all-errors \
	--http1.1 \
	"https://raw.githubusercontent.com/${VENDOR_REPO}/${VENDOR_REF}/manifest_scripts/generate-manifest.sh" \
	-o "${tmp_manifest_script}"
bash "${tmp_manifest_script}"

if [[ ${SKIP_SYNC} -eq 0 ]]; then
	repo sync -j"${JOBS}"
fi

if [[ ${SKIP_LFS} -eq 0 ]]; then
	git -C prebuilts/mesa-tools lfs pull

	if [[ -d external/chromium-webview/prebuilt/arm64 ]]; then
		git -C external/chromium-webview/prebuilt/arm64 lfs install
		git -C external/chromium-webview/prebuilt/arm64 lfs pull
	fi
fi

export USE_CCACHE=1
export CCACHE_DIR
export CCACHE_EXEC="$(command -v ccache)"
ccache -M 20G >/dev/null

if [[ ${BUILD_GAPPS} -eq 1 ]]; then
	export ANDROID_BUILD_GAPPS=true
else
	unset ANDROID_BUILD_GAPPS || true
fi

source build/envsetup.sh
apply-waydroid-patches
apply_patch_if_needed "${ANDROID_TOP}" "${PATCH_FILE}"

lunch lineage_waydroid_arm64_only-bp2a-userdebug
make systemimage -j"${JOBS}"
make vendorimage -j"${JOBS}"

PRODUCT_OUT=$(detect_product_out "${ANDROID_TOP}")
install -m0644 "${PRODUCT_OUT}/system.img" "${OUT_DIR}/system.img"
install -m0644 "${PRODUCT_OUT}/vendor.img" "${OUT_DIR}/vendor.img"

(
	cd "${OUT_DIR}"
	sha256sum system.img vendor.img > SHA256SUMS
)

printf 'Images copied to %s\n' "${OUT_DIR}"
