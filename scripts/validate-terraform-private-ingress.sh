#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_ROOT="$REPO_ROOT/terraform"

failures=0

require_pattern() {
    local pattern="$1"
    local path="$2"

    if ! rg --quiet --fixed-strings "$pattern" "$path"; then
        printf 'Missing private-ingress invariant: %s in %s\n' "$pattern" "$path" >&2
        failures=$((failures + 1))
    fi
}

require_pattern 'Cloudflare Tunnel -> APISIX -> private workload upstream' \
    "$TERRAFORM_ROOT/modules/connectivity/README.md"
require_pattern 'create_public_ip_address      = false' \
    "$TERRAFORM_ROOT/modules/private-vm/main.tf"
require_pattern 'private_ip_subnet_resource_id' \
    "$TERRAFORM_ROOT/modules/private-vm/main.tf"

if rg --line-number --glob '*.tf' \
    'create_public_ip_address\s*=\s*true|public_ip_address_id\s*=' \
    "$TERRAFORM_ROOT/modules/private-vm" "$TERRAFORM_ROOT/modules/application-landing-zone"; then
    printf 'Private VM or application landing-zone modules contain a public IP setting.\n' >&2
    failures=$((failures + 1))
fi

if ((failures > 0)); then
    printf 'Private ingress validation failed with %d violation(s).\n' "$failures" >&2
    exit 1
fi

printf 'Private ingress validation passed.\n'
