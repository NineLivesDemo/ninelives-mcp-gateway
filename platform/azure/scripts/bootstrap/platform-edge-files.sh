install -d -m 0755 /opt/platform/compose/edge
install -d -m 0755 /opt/platform/config/edge

cat > /opt/platform/compose/edge/compose.yaml <<'__PLATFORM_EDGE_COMPOSE_EOF__'
__PLATFORM_EDGE_COMPOSE_CONTENT__
__PLATFORM_EDGE_COMPOSE_EOF__

cat > /opt/platform/config/edge/apisix.yaml <<'__PLATFORM_EDGE_APISIX_EOF__'
__PLATFORM_EDGE_APISIX_CONTENT__
__PLATFORM_EDGE_APISIX_EOF__
chmod 0644 /opt/platform/config/edge/apisix.yaml

cat > /opt/platform/compose/edge/registry-route.template.json <<'__PLATFORM_EDGE_ROUTE_EOF__'
__PLATFORM_EDGE_ROUTE_CONTENT__
__PLATFORM_EDGE_ROUTE_EOF__
chmod 0644 /opt/platform/compose/edge/registry-route.template.json

cat > /opt/platform/compose/edge/keycloak-route.template.json <<'__PLATFORM_KEYCLOAK_ROUTE_EOF__'
__PLATFORM_KEYCLOAK_ROUTE_CONTENT__
__PLATFORM_KEYCLOAK_ROUTE_EOF__
chmod 0644 /opt/platform/compose/edge/keycloak-route.template.json

cat > /opt/platform/config/edge/edge-origin.env.example <<'__PLATFORM_EDGE_ORIGIN_EOF__'
__PLATFORM_EDGE_ORIGIN_CONTENT__
__PLATFORM_EDGE_ORIGIN_EOF__

cat > /usr/local/sbin/platform-edge-render <<'__PLATFORM_EDGE_RENDER_EOF__'
__PLATFORM_EDGE_RENDER_CONTENT__
__PLATFORM_EDGE_RENDER_EOF__
chmod 0750 /usr/local/sbin/platform-edge-render

cat > /usr/local/sbin/platform-edge-bootstrap.sh <<'__PLATFORM_EDGE_BOOTSTRAP_EOF__'
__PLATFORM_EDGE_BOOTSTRAP_CONTENT__
__PLATFORM_EDGE_BOOTSTRAP_EOF__
chmod 0755 /usr/local/sbin/platform-edge-bootstrap.sh

cat > /etc/systemd/system/platform-edge-env.service <<'__PLATFORM_EDGE_ENV_UNIT_EOF__'
__PLATFORM_EDGE_ENV_UNIT__
__PLATFORM_EDGE_ENV_UNIT_EOF__

cat > /etc/systemd/system/platform-edge.service <<'__PLATFORM_EDGE_UNIT_EOF__'
__PLATFORM_EDGE_UNIT__
__PLATFORM_EDGE_UNIT_EOF__
