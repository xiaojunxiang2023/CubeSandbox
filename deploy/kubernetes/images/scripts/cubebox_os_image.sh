# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Tencent. All rights reserved.
#
# Shared helper: keep cubebox_os_image artifacts on the data disk while
# preserving the historical toolbox path via a symlink.
# Callers must define fail()/die(); log() is optional.
#
# Final layout: <toolbox>/cubebox_os_image -> /data/cubebox_os_image
# Matches one-click: large template rootfs on the data disk; cubelet keeps
# using the historical toolbox path.

if [[ "${CUBE_CUBEBOX_OS_IMAGE_LIB_LOADED:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi
CUBE_CUBEBOX_OS_IMAGE_LIB_LOADED=1

if ! type fail >/dev/null 2>&1; then
  if type die >/dev/null 2>&1; then
    fail() { die "$@"; }
  else
    fail() {
      echo "[cubebox_os_image] ERROR: $*" >&2
      exit 1
    }
  fi
fi

CUBEBOX_OS_IMAGE_DATA_DIR_DEFAULT="/data/cubebox_os_image"

# ensure_cubebox_os_image_on_data [toolbox_root] [data_dir]
ensure_cubebox_os_image_on_data() {
  local toolbox_root="${1:-${TOOLBOX_ROOT:-/usr/local/services/cubetoolbox}}"
  local data_path="${2:-${CUBEBOX_OS_IMAGE_DATA_DIR:-${CUBEBOX_OS_IMAGE_DATA_DIR_DEFAULT}}}"
  local link_path="${toolbox_root%/}/cubebox_os_image"

  [[ -n "${toolbox_root}" ]] || fail "toolbox root is empty"
  [[ "${data_path}" == /* ]] || fail "cubebox_os_image data dir must be absolute: ${data_path}"
  [[ "${link_path}" == /* ]] || fail "cubebox_os_image link path must be absolute: ${link_path}"

  mkdir -p "$(dirname "${data_path}")"
  mkdir -p "${toolbox_root}"

  if [[ -L "${link_path}" ]]; then
    local current
    current="$(readlink "${link_path}")"
    if [[ "${current}" == "${data_path}" ]]; then
      mkdir -p "${data_path}"
      return 0
    fi
    rm -f "${link_path}"
  elif [[ -d "${link_path}" ]]; then
    if [[ -e "${data_path}" && ! -d "${data_path}" ]]; then
      fail "refusing to migrate cubebox_os_image: ${data_path} exists and is not a directory"
    fi
    if [[ ! -d "${data_path}" ]]; then
      mkdir -p "$(dirname "${data_path}")"
      mv "${link_path}" "${data_path}"
    else
      if [[ -n "$(find "${link_path}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]]; then
        cp -a "${link_path}/." "${data_path}/"
      fi
      rm -rf "${link_path}"
    fi
  elif [[ -e "${link_path}" ]]; then
    fail "refusing to replace non-directory cubebox_os_image path: ${link_path}"
  fi

  mkdir -p "${data_path}"
  ln -sfn "${data_path}" "${link_path}"

  if declare -F log >/dev/null 2>&1; then
    log "cubebox_os_image ready: ${link_path} -> ${data_path}"
  fi
}
