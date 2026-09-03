#!/usr/bin/env bash
# 为离线 ezone 同步社区 v0.7.0 双架构镜像:
# - 普通组件: skopeo --all 整份 multi-arch 拷到 ezone (不编译)
# - cubelet / cube-node-init: 社区 multi-arch base 上按 arch 叠软链脚本, 再合 manifest
#
# 社区已提供 linux/amd64 + linux/arm64 (cube-sandbox-int / ghcr).
#
# 用法 (ubuntu22 + docker + skopeo + buildx):
#   PUSH=1 ./deploy/kubernetes/dist/build-push-ezone.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/deploy/kubernetes/images/scripts"
OVERLAY_DIR="${REPO_ROOT}/deploy/kubernetes/dist/overlay"
REGISTRY="${REGISTRY:-ezone.ksyun.com/ezone/kdxe_docker/snapshot/kdxe}"
COMMUNITY_REGISTRY="${COMMUNITY_REGISTRY:-cube-sandbox-int.tencentcloudcr.com/cube-sandbox}"
IMAGE_TAG="${IMAGE_TAG:-v0.7.0}"
PUSH="${PUSH:-1}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER="${BUILDER:-cube-proxy-builder}"

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

OVERLAY_IMAGES=(cubelet cube-node-init)

log() { printf '[build-push-ezone] %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { log "missing required command: $1"; exit 1; }; }

need docker
need skopeo
docker info >/dev/null

# buildx builder (多架构 overlay 需要)
if ! docker buildx inspect "${BUILDER}" >/dev/null 2>&1; then
  docker buildx create --name "${BUILDER}" --driver docker-container --use
fi
docker buildx use "${BUILDER}"
docker buildx inspect --bootstrap >/dev/null

log "registry=${REGISTRY} community=${COMMUNITY_REGISTRY} tag=${IMAGE_TAG} platforms=${PLATFORMS} push=${PUSH}"

# 整份 multi-arch 清单拷贝 (保留 amd64+arm64).
mirror_one() {
  local name="$1"
  local tag="${2:-${IMAGE_TAG}}"
  local src="docker://${COMMUNITY_REGISTRY}/${name}:${tag}"
  local dst="docker://${REGISTRY}/${name}:${tag}"
  log "=== mirror ${name}:${tag} (skopeo --all) ==="
  if [[ "${PUSH}" != "1" ]]; then
    log "PUSH=0 skip copy to ezone"
    return 0
  fi
  local i
  for i in 1 2 3 4 5 6 7 8; do
    log "skopeo copy attempt ${i}: ${name}:${tag}"
    if skopeo copy --all --dest-tls-verify=false "${src}" "${dst}"; then
      return 0
    fi
    sleep $((4 + i))
  done
  log "skopeo copy failed: ${name}:${tag}"
  return 1
}

# 按平台叠脚本, 推 arch tag, 再合 multi-arch :tag
overlay_one() {
  local name="$1"
  local src="${COMMUNITY_REGISTRY}/${name}:${IMAGE_TAG}"
  local dst="${REGISTRY}/${name}:${IMAGE_TAG}"
  local df="${OVERLAY_DIR}/Dockerfile.${name}"
  [[ -f "${df}" ]] || { log "missing overlay Dockerfile: ${df}"; exit 1; }

  log "=== overlay ${name} multi-arch (FROM ${src}) ==="
  local arch_tags=()
  local plat arch dst_arch
  IFS=',' read -r -a plats <<< "${PLATFORMS}"
  for plat in "${plats[@]}"; do
    plat="$(echo "${plat}" | tr -d ' ')"
    arch="${plat##*/}"
    dst_arch="${dst}-${arch}"
    log "buildx ${plat} -> ${dst_arch}"
    DOCKER_BUILDKIT_NO_CLIENT_ATTESTATIONS=1 docker buildx build \
      --builder "${BUILDER}" \
      --platform "${plat}" \
      --network host \
      --provenance=false --sbom=false \
      --build-arg "BASE_IMAGE=${src}" \
      -f "${df}" \
      -t "${dst_arch}" \
      --push \
      "${SCRIPTS_DIR}"
    arch_tags+=("${dst_arch}")
  done

  if [[ "${PUSH}" == "1" ]]; then
    # ezone 偶发 push 后 tag/layer 短暂不可见, 合清单需重试
    local i
    for i in 1 2 3 4 5 6 7 8; do
      log "imagetools create attempt ${i}: ${dst}"
      sleep $((2 + i * 2))
      if docker buildx imagetools create --tag "${dst}" "${arch_tags[@]}"; then
        return 0
      fi
    done
    log "imagetools create failed: ${dst}"
    return 1
  fi
}

for name in "${MIRROR_IMAGES[@]}"; do
  mirror_one "${name}"
done

for name in "${OVERLAY_IMAGES[@]}"; do
  overlay_one "${name}"
done

log "=== alpine-k8s:1.28.15 ==="
mirror_one alpine-k8s "1.28.15"

log "done. verifying platforms..."
for name in "${MIRROR_IMAGES[@]}" "${OVERLAY_IMAGES[@]}"; do
  printf '  %s/%s:%s\n' "${REGISTRY}" "${name}" "${IMAGE_TAG}"
  docker buildx imagetools inspect "${REGISTRY}/${name}:${IMAGE_TAG}" 2>/dev/null | grep 'Platform:' || true
done
printf '  %s/alpine-k8s:1.28.15\n' "${REGISTRY}"
docker buildx imagetools inspect "${REGISTRY}/alpine-k8s:1.28.15" 2>/dev/null | grep 'Platform:' || true
