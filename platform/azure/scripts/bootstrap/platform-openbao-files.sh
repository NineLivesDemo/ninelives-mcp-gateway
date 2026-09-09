install -d -m 0750 /opt/platform/compose/openbao
install -d -m 0755 /opt/platform/config/openbao
install -d -m 0750 /etc/platform/config

cat > /opt/platform/compose/openbao/compose.yaml <<'__PLATFORM_OPENBAO_COMPOSE_EOF__'
__PLATFORM_OPENBAO_COMPOSE_CONTENT__
__PLATFORM_OPENBAO_COMPOSE_EOF__

cat > /opt/platform/config/openbao/openbao.hcl <<'__PLATFORM_OPENBAO_HCL_EOF__'
__PLATFORM_OPENBAO_HCL_CONTENT__
__PLATFORM_OPENBAO_HCL_EOF__
chmod 0644 /opt/platform/config/openbao/openbao.hcl

cat > /etc/platform/config/openbao.env <<'__PLATFORM_OPENBAO_ENV_EOF__'
__PLATFORM_OPENBAO_ENV_CONTENT__
__PLATFORM_OPENBAO_ENV_EOF__
chmod 0640 /etc/platform/config/openbao.env

cat > /etc/systemd/system/platform-openbao.service <<'__PLATFORM_OPENBAO_UNIT_EOF__'
__PLATFORM_OPENBAO_UNIT__
__PLATFORM_OPENBAO_UNIT_EOF__
