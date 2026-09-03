#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Guard: cubebox_os_image softlink helper migrates real dirs and is idempotent.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/cubebox_os_image.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

toolbox="${TMP_DIR}/toolbox"
data="${TMP_DIR}/data/cubebox_os_image"
mkdir -p "${toolbox}"

ensure_cubebox_os_image_on_data "${toolbox}" "${data}"
[[ -L "${toolbox}/cubebox_os_image" ]] || {
  echo "expected symlink at ${toolbox}/cubebox_os_image" >&2
  exit 1
}
[[ "$(readlink "${toolbox}/cubebox_os_image")" == "${data}" ]] || {
  echo "symlink target mismatch" >&2
  exit 1
}
[[ -d "${data}" ]] || {
  echo "data dir missing" >&2
  exit 1
}

ensure_cubebox_os_image_on_data "${toolbox}" "${data}"

toolbox2="${TMP_DIR}/toolbox2"
data2="${TMP_DIR}/data2/cubebox_os_image"
mkdir -p "${toolbox2}/cubebox_os_image"
echo payload >"${toolbox2}/cubebox_os_image/keep.txt"
ensure_cubebox_os_image_on_data "${toolbox2}" "${data2}"
[[ -L "${toolbox2}/cubebox_os_image" ]] || {
  echo "migration should leave a symlink" >&2
  exit 1
}
[[ -f "${data2}/keep.txt" ]] || {
  echo "migration should move content to data dir" >&2
  exit 1
}

echo "cubebox_os_image softlink helper OK"
