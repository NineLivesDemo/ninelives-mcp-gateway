install -d -m 0755 /opt/platform/compose/keycloak

cat > /opt/platform/compose/keycloak/compose.yaml <<'__PLATFORM_KEYCLOAK_COMPOSE_EOF__'
__PLATFORM_KEYCLOAK_COMPOSE_CONTENT__
__PLATFORM_KEYCLOAK_COMPOSE_EOF__
chmod 0644 /opt/platform/compose/keycloak/compose.yaml

cat > /usr/local/sbin/platform-keycloak-render <<'__PLATFORM_KEYCLOAK_RENDER_EOF__'
__PLATFORM_KEYCLOAK_RENDER_CONTENT__
__PLATFORM_KEYCLOAK_RENDER_EOF__
chmod 0750 /usr/local/sbin/platform-keycloak-render

cat > /etc/systemd/system/platform-keycloak-env.service <<'__PLATFORM_KEYCLOAK_ENV_EOF__'
__PLATFORM_KEYCLOAK_ENV_UNIT__
__PLATFORM_KEYCLOAK_ENV_EOF__

cat > /etc/systemd/system/platform-keycloak.service <<'__PLATFORM_KEYCLOAK_UNIT_EOF__'
__PLATFORM_KEYCLOAK_UNIT__
__PLATFORM_KEYCLOAK_UNIT_EOF__
