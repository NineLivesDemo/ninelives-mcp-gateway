#!/usr/bin/env bash

set -euo pipefail
umask 077

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    printf 'Usage: %s KEY_VAULT_NAME SECRET_DIRECTORY [--dry-run]\n' "$0" >&2
    exit 64
fi

VAULT_NAME="$1"
SECRET_DIRECTORY="$(realpath "$2")"
DRY_RUN=false
if [ "$#" -eq 3 ]; then
    if [ "$3" != "--dry-run" ]; then
        printf 'Unknown option: %s\n' "$3" >&2
        exit 64
    fi
    DRY_RUN=true
fi

if [[ ! "$VAULT_NAME" =~ ^[A-Za-z0-9-]{3,24}$ ]]; then
    printf 'Invalid Key Vault name: %s\n' "$VAULT_NAME" >&2
    exit 64
fi

if [ ! -d "$SECRET_DIRECTORY" ]; then
    printf 'Secret directory does not exist: %s\n' "$SECRET_DIRECTORY" >&2
    exit 1
fi

readonly REQUIRED_SECRETS=(
    cloudflare-tunnel-token
    apisix-admin-key
    grafana-otlp-edge
    grafana-otlp-etcd
    grafana-otlp-openbao
    platform-ca-cert
    etcd-server-cert
    etcd-server-key
    etcd-edge-client-cert
    etcd-edge-client-key
    etcd-health-client-cert
    etcd-health-client-key
    openbao-tls-cert
    openbao-tls-key
)

for secret_name in "${REQUIRED_SECRETS[@]}"; do
    secret_file="$SECRET_DIRECTORY/$secret_name"
    if [ -L "$secret_file" ] || [ ! -f "$secret_file" ]; then
        printf 'Missing regular secret file: %s\n' "$secret_file" >&2
        exit 1
    fi
done

for secret_name in "${REQUIRED_SECRETS[@]}"; do
    secret_file="$SECRET_DIRECTORY/$secret_name"
    if [ "$DRY_RUN" = true ]; then
        printf 'would_seed=%s\n' "$secret_name"
        continue
    fi

    az keyvault secret set \
        --only-show-errors \
        --vault-name "$VAULT_NAME" \
        --name "$secret_name" \
        --file "$secret_file" \
        >/dev/null
    printf 'seeded=%s\n' "$secret_name"
done

if [ "$DRY_RUN" = true ]; then
    printf 'dry_run=true vault=%s count=%s\n' "$VAULT_NAME" "${#REQUIRED_SECRETS[@]}"
else
    printf 'seeded=true vault=%s count=%s\n' "$VAULT_NAME" "${#REQUIRED_SECRETS[@]}"
fi
