install -d -m 0755 /opt/platform/compose/etcd

cat > /opt/platform/compose/etcd/compose.yaml <<'__PLATFORM_ETCD_COMPOSE_EOF__'
__PLATFORM_ETCD_COMPOSE_CONTENT__
__PLATFORM_ETCD_COMPOSE_EOF__

cat > /etc/systemd/system/platform-etcd.service <<'__PLATFORM_ETCD_UNIT_EOF__'
__PLATFORM_ETCD_UNIT__
__PLATFORM_ETCD_UNIT_EOF__
