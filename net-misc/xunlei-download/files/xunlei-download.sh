#!/bin/sh
runtime_dir=/opt/xunlei-download
export LD_LIBRARY_PATH="${runtime_dir}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
# The legacy client writes BHO/config.ini before creating its parent directory.
data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}"
mkdir -p "${data_dir}/ThunderNetwork/profiles/Thunder/BHO" || exit 1
exec "${runtime_dir}/thunder" "$@"
