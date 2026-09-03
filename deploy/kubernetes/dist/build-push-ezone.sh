#!/usr/bin/env bash
# 为 openeuler147 离线环境把社区 v0.7.0 镜像弄到 ezone:
# - 普通组件: pull 社区 → tag → push ezone (不编译)
# - cubelet / cube-node-init: 社区 base 上叠 kdxe 软链脚本再 push (不编 Go)
#
# 用法 (ubuntu22 等 amd64 + docker):
#   REGISTRY=ezone.ksyun.com/ezone/kdxe_docker/snapshot/kdxe \
#   IMAGE_TAG=v0.7.0 PUSH=1 ./deploy/kubernetes/dist/build-push-ezone.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/deploy/kubernetes/images/scripts"
OVERLAY_DIR="${REPO_ROOT}/deploy/kubernetes/dist/overlay"
REGISTRY="${REGISTRY:-ezone.ksyun.com/ezone/kdxe_docker/snapshot/kdxe}"
COMMUNITY_REGISTRY="${COMMUNITY_REGISTRY:-cube-sandbox-int.tencentcloudcr.com/cube-sandbox}"
IMAGE_TAG="${IMAGE_TAG:-v0.7.0}"
PUSH="${PUSH:-1}"

# 仅镜像转发 (与社区同内容).
MIRROR_IMAGES=(
  cube-master
  cube-api
  cube-ops
  cubemastercli
  cube-proxy
  cube-lifecycle-manager
  cube-shim
  cube-kernel
  cube-guest
  cube-agent
  cube-wait-node-prep
)

# 社区 base + 软链脚本 overlay.
OVERLAY_IMAGES=(cubelet cube-node-init)

log() { printf '[build-push-ezone] %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { log "missing required command: $1"; exit 1; }; }

push_retry() {
  local img="$1" i
  for i in 1 2 3 4 5 6 7 8; do
    log "push attempt ${i}: ${img}"
    if docker push "${img}"; then
      return 0
    fi
    sleep $((4 + i))
  done
  log "push failed: ${img}"
  return 1
}

need docker
docker info >/dev/null

log "registry=${REGISTRY} community=${COMMUNITY_REGISTRY} tag=${IMAGE_TAG} push=${PUSH}"

mirror_one() {
  local name="$1"
  local src="${COMMUNITY_REGISTRY}/${name}:${IMAGE_TAG}"
  local dst="${REGISTRY}/${name}:${IMAGE_TAG}"
  log "=== mirror ${name} ==="
  log "pull ${src}"
  docker pull "${src}"
  docker tag "${src}" "${dst}"
  if [[ "${PUSH}" == "1" ]]; then
    push_retry "${dst}"
  fi
}

overlay_one() {
  local name="$1"
  local src="${COMMUNITY_REGISTRY}/${name}:${IMAGE_TAG}"
  local dst="${REGISTRY}/${name}:${IMAGE_TAG}"
  local df="${OVERLAY_DIR}/Dockerfile.${name}"
  [[ -f "${df}" ]] || { log "missing overlay Dockerfile: ${df}"; exit 1; }
  log "=== overlay ${name} (FROM ${src}) ==="
  docker pull "${src}"
  docker build --network host \
    --build-arg "BASE_IMAGE=${src}" \
    -f "${df}" \
    -t "${dst}" \
    "${SCRIPTS_DIR}"
  if [[ "${PUSH}" == "1" ]]; then
    push_retry "${dst}"
  fi
}

for name in "${MIRROR_IMAGES[@]}"; do
  mirror_one "${name}"
done

for name in "${OVERLAY_IMAGES[@]}"; do
  overlay_one "${name}"
done

# alpine-k8s hook image.
ALPINE_K8S="${REGISTRY}/alpine-k8s:1.28.15"
if ! docker manifest inspect "${ALPINE_K8S}" >/dev/null 2>&1; then
  log "=== alpine-k8s (retag from community mirror) ==="
  SRC="${COMMUNITY_REGISTRY}/alpine-k8s:1.28.15"
  # 社区 alpine-k8s 也可能在同 registry; 若失败再试旧路径
  if ! docker pull "${SRC}"; then
    SRC="cube-sandbox-int.tencentcloudcr.com/cube-sandbox/alpine-k8s:1.28.15"
    docker pull "${SRC}"
  fi
  docker tag "${SRC}" "${ALPINE_K8S}"
  if [[ "${PUSH}" == "1" ]]; then
    push_retry "${ALPINE_K8S}"
  fi
fi

log "done."
for name in "${MIRROR_IMAGES[@]}" "${OVERLAY_IMAGES[@]}"; do
  printf '  %s/%s:%s\n' "${REGISTRY}" "${name}" "${IMAGE_TAG}"
done
printf '  %s\n' "${ALPINE_K8S}"
