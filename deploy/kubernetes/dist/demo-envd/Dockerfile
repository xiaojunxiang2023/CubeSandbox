# 极简模板试跑镜像: python enhance 为 base, 再叠 envd + cube-entrypoint (同 openclaw 从 cube_base 拷)
# 双架构构建见 build-push.sh

FROM ezone.ksyun.com/ezone/kdxe_docker/snapshot/kdxe/cube_base:1.0 AS cube_base

FROM ezone.ksyun.com/ezone/kdxe_docker/snapshot/kdxe-multi/python:3.12-enhance

COPY --from=cube_base /usr/bin/envd /usr/bin/envd
COPY --from=cube_base /usr/bin/cube-entrypoint.sh /usr/bin/cube-entrypoint.sh

RUN chmod 755 /usr/bin/envd /usr/bin/cube-entrypoint.sh \
 && /usr/bin/envd -h >/dev/null 2>&1 || true

# 无 CMD: entrypoint 前台等 envd, 满足模板探针 :49983/health
ENTRYPOINT ["/usr/bin/cube-entrypoint.sh"]
