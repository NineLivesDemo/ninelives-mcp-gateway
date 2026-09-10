#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$REPO_ROOT/terraform/env/dev"
INVENTORY_PATH="$REPO_ROOT/ansible/inventory/terraform.json"

mkdir -p "$(dirname "$INVENTORY_PATH")"
terraform -chdir="$TERRAFORM_DIR" output -json ansible_hosts > "$INVENTORY_PATH"
chmod 600 "$INVENTORY_PATH"
printf 'Generated Ansible inventory at %s\n' "$INVENTORY_PATH"
