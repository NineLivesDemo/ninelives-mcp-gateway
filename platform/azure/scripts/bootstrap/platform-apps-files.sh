install -d -m 0755 /opt/platform/compose/apps
install -d -m 0755 /opt/platform/config/apps
install -d -m 0750 /var/lib/platform/apps/registry/servers
install -d -m 0750 /var/lib/platform/apps/registry/agents
install -d -m 0750 /var/lib/platform/apps/registry/models
install -d -m 0750 /var/lib/platform/apps/registry/security_scans
install -d -m 0750 /var/log/containers/ai-registry
chown -R 1000:1000 /var/lib/platform/apps/registry /var/log/containers/ai-registry

cat > /usr/local/sbin/platform-acr-login <<'__PLATFORM_ACR_LOGIN_EOF__'
#!/usr/bin/env bash
set -Eeuo pipefail

az login --identity --allow-no-subscriptions --output none
az acr login --name __PLATFORM_ACR_NAME__ --only-show-errors
__PLATFORM_ACR_LOGIN_EOF__
chmod 0750 /usr/local/sbin/platform-acr-login

cat > /opt/platform/compose/apps/compose.yaml <<'__PLATFORM_APPS_COMPOSE_EOF__'
__PLATFORM_APPS_COMPOSE_CONTENT__
__PLATFORM_APPS_COMPOSE_EOF__
chmod 0644 /opt/platform/compose/apps/compose.yaml

cat > /usr/local/sbin/platform-apps-render <<'__PLATFORM_APPS_RENDER_EOF__'
__PLATFORM_APPS_RENDER_CONTENT__
__PLATFORM_APPS_RENDER_EOF__
chmod 0750 /usr/local/sbin/platform-apps-render

cat > /etc/systemd/system/platform-apps-env.service <<'__PLATFORM_APPS_ENV_UNIT_EOF__'
__PLATFORM_APPS_ENV_UNIT__
__PLATFORM_APPS_ENV_UNIT_EOF__

cat > /etc/systemd/system/platform-apps.service <<'__PLATFORM_APPS_UNIT_EOF__'
__PLATFORM_APPS_UNIT__
__PLATFORM_APPS_UNIT_EOF__
