#!/usr/bin/env python3
# 极简: 建模板 + 起实例. 默认按「集群内 Pod」访问 API Service.
# 本机/port-forward 时设: CUBE_API_URL=http://127.0.0.1:3000

from __future__ import annotations

import os
import time

from cubesandbox import Config, Sandbox, Template

API_URL = os.environ.get(
    "CUBE_API_URL", "http://cubesandbox-api.cube-system.svc.cluster.local:3000"
)
# 集群内默认走 Proxy Service; 集群外再设 CUBE_PROXY_NODE_IP / CUBE_PROXY_PORT_HTTP
PROXY_IP = os.environ.get(
    "CUBE_PROXY_NODE_IP", "cubesandbox-proxy.cube-system.svc.cluster.local"
)
PROXY_PORT = int(os.environ.get("CUBE_PROXY_PORT_HTTP", "80"))
DOMAIN = os.environ.get("CUBE_SANDBOX_DOMAIN", "cube.app")
IMAGE = os.environ.get(
    "DEMO_IMAGE", "ezone.ksyun.com/ezone/kdxe_docker/snapshot/kdxe/demo-envd:1.0"
)
REG_USER = os.environ.get("REG_USER", "xiaojunxiang")
REG_PASS = os.environ.get("REG_PASS", "0e48b4c15e3b4f298ef54d3ae81c914e1773642431041")

cfg = Config(
    api_url=API_URL,
    proxy_node_ip=PROXY_IP,
    proxy_port=PROXY_PORT,
    sandbox_domain=DOMAIN,
)


def main() -> None:
    print(f"[0] api={API_URL} proxy={PROXY_IP}:{PROXY_PORT}")
    print(f"[1] Template.build image={IMAGE}")
    job = Template.build(
        name="demo-envd",
        image=IMAGE,
        cpu_count=2,
        memory_mb=2048,
        writable_layer_size="2G",
        exposed_ports=[49983],
        probe_port=49983,
        probe_path="/health",
        allow_internet_access=True,
        registry_username=REG_USER,
        registry_password=REG_PASS,
        with_cube_ca=False,  # 未开 CubeEgress, 不要烤 CA
        config=cfg,
    )
    tid, bid = job.template_id, job.build_id
    print(f"    template_id={tid} build_id={bid}")

    print("[2] wait build...")
    while True:
        st = Template.get_build_status(tid, bid, config=cfg)
        phase = (st.phase or st.status or "").lower()
        print(f"    phase={phase} progress={st.progress} msg={st.message or st.error_message}")
        if phase in ("succeeded", "success", "completed", "ready", "done"):
            break
        if phase in ("failed", "error", "cancelled", "canceled"):
            raise SystemExit(f"build failed: {st.error_message or st.message}")
        time.sleep(5)

    print(f"[3] Sandbox.create template={tid}")
    sb = Sandbox.create(template=tid, timeout=300, config=cfg)
    print(f"    sandbox_id={sb.sandbox_id}")
    r = sb.commands.run("python3 -c 'print(\"hello from demo-envd\")' && uname -m")
    print(f"[4] exit={r.exit_code}\n{r.stdout}\n{r.stderr}")
    if r.exit_code != 0:
        raise SystemExit("command failed")
    print("[ok] demo passed (sandbox kept alive, not killed)")
    print(f"    reuse: sandbox_id={sb.sandbox_id}")


if __name__ == "__main__":
    main()
