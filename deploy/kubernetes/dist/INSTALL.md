# Offline install (ezone only): community images mirrored + kdxe overlay for softlink

## Files

| File | Description |
|------|-------------|
| `values-openeuler147.yaml` | Environment-specific values |
| `build-push-ezone.sh` | Mirror community → ezone; overlay softlink on cubelet/node-init |
| `overlay/` | Thin Dockerfiles: `FROM` community, COPY softlink scripts only |

Helm chart tgz 安装前自行打包, 例如:

```bash
helm package deploy/kubernetes/chart -d deploy/kubernetes/dist
# -> cube-0.7.0.tgz
```

## Images

| Type | Images | How |
|------|--------|-----|
| Mirror | master, api, ops, cubemastercli, proxy, lifecycle-manager, shim, kernel, guest, agent, wait-node-prep, alpine-k8s | pull 社区 → tag ezone (不编译) |
| Overlay (kdxe) | node-init, cubelet | 社区 `v0.7.0` 为 base, 只叠 cubebox_os_image 软链脚本 |

在 ubuntu22 上推 ezone:

```bash
PUSH=1 ./deploy/kubernetes/dist/build-push-ezone.sh
```

Verify with `k3s ctr images pull` before install.

CubeProxy is exposed on NodePort **30082** (HTTP, Service port 80). Example: `http://10.148.51.147:30082` (or `http://<sandbox-id>.cube.app:30082` when DNS points at the control node). HTTPS / gRPC / admin NodePorts are auto-allocated unless you pin them under `cubeProxy.service.nodePorts`.

## Install

```bash
helm upgrade --install cube ./cube-0.7.0.tgz \
  -n cube-system --create-namespace \
  -f values-openeuler147.yaml \
  --wait --timeout 90m
```
