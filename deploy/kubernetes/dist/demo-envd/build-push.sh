#!/usr/bin/env bash
# 双架构推 ezone: demo-envd:1.0
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
REG="${REG:-ezone.ksyun.com/ezone/kdxe_docker/snapshot/kdxe}"
TAG="${TAG:-demo-envd:1.0}"
DST="${REG}/${TAG}"
BUILDER="${BUILDER:-cube-proxy-builder}"

need() { command -v "$1" >/dev/null || { echo "missing $1"; exit 1; }; }
need docker
need skopeo

if ! docker buildx inspect "${BUILDER}" >/dev/null 2>&1; then
  docker buildx create --name "${BUILDER}" --driver docker-container --use
fi
docker buildx use "${BUILDER}"

echo "[demo-envd] build+push ${DST} (amd64+arm64)"

# amd64: load + docker push (避开 buildx 直推鉴权问题)
DOCKER_BUILDKIT_NO_CLIENT_ATTESTATIONS=1 docker buildx build \
  --builder "${BUILDER}" --platform linux/amd64 --network host \
  --provenance=false --sbom=false \
  -f "${ROOT}/Dockerfile" -t "${DST}-amd64" --load "${ROOT}"
for i in 1 2 3 4 5 6 7 8; do
  docker push "${DST}-amd64" && break
  sleep $((4 + i))
  [[ $i -eq 8 ]] && exit 1
done

# arm64: oci 目录 + skopeo
rm -rf /tmp/demo-envd-arm64.oci
DOCKER_BUILDKIT_NO_CLIENT_ATTESTATIONS=1 docker buildx build \
  --builder "${BUILDER}" --platform linux/arm64 --network host \
  --provenance=false --sbom=false \
  -f "${ROOT}/Dockerfile" -o type=oci,dest=/tmp/demo-envd-arm64.oci,tar=false "${ROOT}"
for i in 1 2 3 4 5 6 7 8; do
  skopeo copy --dest-tls-verify=false --all \
    oci:/tmp/demo-envd-arm64.oci "docker://${DST}-arm64" && break
  sleep $((4 + i))
  [[ $i -eq 8 ]] && exit 1
done

for i in 1 2 3 4 5 6 7 8; do
  sleep $((2 + i * 2))
  docker buildx imagetools create --tag "${DST}" "${DST}-amd64" "${DST}-arm64" && break
done

docker buildx imagetools inspect "${DST}" | grep Platform
echo "[demo-envd] ok ${DST}"
