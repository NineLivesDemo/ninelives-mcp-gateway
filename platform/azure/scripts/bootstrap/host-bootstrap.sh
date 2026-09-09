#!/usr/bin/env bash
set -Eeuo pipefail

ROLE="__PLATFORM_ROLE__"
ALLOY_VERSION="1.19.2-1"
DATA_DEVICE="/dev/disk/azure/scsi1/lun0"
DATA_MOUNT="/var/lib/platform/data"
FORMAT_DATA_DISK="__PLATFORM_FORMAT_DATA_DISK__"
ENABLE_PYTHON310_COMPAT="__PLATFORM_ENABLE_PYTHON310_COMPAT__"

umask 027
exec > >(logger -t platform-host-bootstrap) 2>&1

if [[ "${ROLE}" == __* || "${FORMAT_DATA_DISK}" == __* || "${ENABLE_PYTHON310_COMPAT}" == __* ]]; then
  echo "The platform VM bootstrap placeholders were not rendered." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install --yes --no-install-recommends \
  ca-certificates \
  curl \
  docker-compose-v2 \
  docker.io \
  gpg \
  jq \
  python3

if [[ "${ROLE}" == "apps" ]]; then
  install -d -m 0755 /etc/apt/keyrings
  curl --fail --silent --show-error --location --retry 3 --max-time 30 \
    https://packages.microsoft.com/keys/microsoft.asc \
    --output /tmp/microsoft.asc
  gpg --dearmor --yes --output /etc/apt/keyrings/microsoft.gpg /tmp/microsoft.asc
  rm -f /tmp/microsoft.asc
  chmod 0644 /etc/apt/keyrings/microsoft.gpg
  . /etc/os-release
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ %s main\n' \
    "$(dpkg --print-architecture)" "${VERSION_CODENAME}" \
    > /etc/apt/sources.list.d/azure-cli.list
  apt-get update
  apt-get install --yes --no-install-recommends azure-cli
fi

install -d -m 0755 /etc/apt/keyrings
curl --fail --silent --show-error --location --retry 3 --max-time 30 \
  https://apt.grafana.com/gpg-full.key \
  --output /tmp/grafana.asc
gpg --dearmor --yes --output /etc/apt/keyrings/grafana.gpg /tmp/grafana.asc
rm -f /tmp/grafana.asc
chmod 0644 /etc/apt/keyrings/grafana.gpg

printf '%s\n' \
  'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' \
  > /etc/apt/sources.list.d/grafana.list

apt-get update
apt-get install --yes --no-install-recommends "alloy=${ALLOY_VERSION}"
apt-mark hold alloy
systemctl stop alloy.service
systemctl disable alloy.service

install -d -m 0750 /etc/platform
install -d -m 0750 /etc/platform/secrets
install -d -m 0755 /etc/platform/tls
install -d -m 0755 /opt/platform
install -d -m 0750 /opt/platform/bin
install -d -m 0755 /opt/platform/compose
install -d -m 0755 /opt/platform/config
install -d -m 0750 "${DATA_MOUNT}"

printf '%s\n' "${ROLE}" > /etc/platform/role
chmod 0644 /etc/platform/role

cat > /usr/local/sbin/platform-secret-sync <<'__PLATFORM_SECRET_SYNC_CONTENT_EOF__'
__PLATFORM_SECRET_SYNC_CONTENT__
__PLATFORM_SECRET_SYNC_CONTENT_EOF__
chmod 0750 /usr/local/sbin/platform-secret-sync

cat > /etc/platform/secret-sync.json <<'__PLATFORM_SECRET_SYNC_CONFIG_EOF__'
{
  "vaultUri": "__PLATFORM_KEY_VAULT_URI__",
  "secrets": [
__PLATFORM_SECRET_MAPPINGS__
  ]
}
__PLATFORM_SECRET_SYNC_CONFIG_EOF__
chmod 0600 /etc/platform/secret-sync.json

cat > /etc/systemd/system/platform-secret-sync.service <<'__PLATFORM_SECRET_SYNC_UNIT_EOF__'
__PLATFORM_SECRET_SYNC_UNIT__
__PLATFORM_SECRET_SYNC_UNIT_EOF__

cat > /etc/systemd/system/platform-secret-sync.timer <<'__PLATFORM_SECRET_SYNC_TIMER_EOF__'
__PLATFORM_SECRET_SYNC_TIMER__
__PLATFORM_SECRET_SYNC_TIMER_EOF__

__PLATFORM_ROLE_BOOTSTRAP__

if [[ "${ENABLE_PYTHON310_COMPAT}" == "true" ]]; then
  install -d -m 0755 /opt/platform/scripts
  cat > /opt/platform/scripts/install-python310-compat.sh <<'__PLATFORM_PYTHON310_COMPAT_EOF__'
__PLATFORM_PYTHON310_COMPAT_CONTENT__
__PLATFORM_PYTHON310_COMPAT_EOF__
  chmod 0755 /opt/platform/scripts/install-python310-compat.sh
  /opt/platform/scripts/install-python310-compat.sh
fi
if [[ ! -e /etc/docker/daemon.json ]]; then
  install -d -m 0755 /etc/docker
  printf '%s\n' '{"log-driver":"journald"}' > /etc/docker/daemon.json
fi

systemctl enable --now docker.service

if [[ -b "${DATA_DEVICE}" ]]; then
  if ! blkid "${DATA_DEVICE}" >/dev/null 2>&1; then
    if wipefs --no-act "${DATA_DEVICE}" | grep -q .; then
      echo "Data disk has an existing filesystem signature but is not readable." >&2
      exit 1
    fi
    if [[ "${FORMAT_DATA_DISK}" != "true" ]]; then
      echo "Data disk is unformatted and automatic formatting is disabled." >&2
      exit 1
    fi
    mkfs.ext4 -L platform-data "${DATA_DEVICE}"
  fi

  data_uuid="$(blkid -s UUID -o value "${DATA_DEVICE}")"
  if [[ -z "${data_uuid}" ]]; then
    echo "The data disk did not expose a UUID after filesystem preparation." >&2
    exit 1
  fi
  if ! grep -qE "[[:space:]]${DATA_MOUNT}[[:space:]]" /etc/fstab; then
    printf 'UUID=%s %s ext4 defaults,nofail,x-systemd.device-timeout=60 0 2\n' \
      "${data_uuid}" "${DATA_MOUNT}" >> /etc/fstab
  fi
  mountpoint -q "${DATA_MOUNT}" || mount "${DATA_MOUNT}"
fi

chown root:root /etc/platform /etc/platform/secrets /etc/platform/tls
chmod 0750 /etc/platform /etc/platform/secrets
chmod 0755 /etc/platform/tls
systemctl daemon-reload

echo "Platform host bootstrap completed for role ${ROLE}."
