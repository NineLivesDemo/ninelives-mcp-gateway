#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/../infra" && pwd)"
PARAM_FILE="${INFRA_DIR}/main.bicepparam"
LOCATION="westus3"
DEPLOY=false
CONFIRMATION=""

usage() {
  echo "Usage: $0 [--parameters FILE] [--location REGION] [--apply] [--confirm DEPLOY]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parameters)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      PARAM_FILE="$2"
      shift 2
      ;;
    --location)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      LOCATION="$2"
      shift 2
      ;;
    --apply)
      DEPLOY=true
      shift
      ;;
    --confirm)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      CONFIRMATION="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

[[ -f "$PARAM_FILE" ]] || { echo "Parameter file not found: $PARAM_FILE" >&2; exit 1; }
[[ -n "${AZURE_ADMIN_PUBLIC_KEY:-}" ]] || {
  echo "AZURE_ADMIN_PUBLIC_KEY must be set in the environment; it is never passed as a CLI secret." >&2
  exit 1
}
command -v az >/dev/null || { echo "Azure CLI (az) is required in WSL." >&2; exit 1; }
az account show >/dev/null

az deployment sub validate \
  --location "$LOCATION" \
  --template-file "${INFRA_DIR}/main.bicep" \
  --parameters "$PARAM_FILE" \
  --only-show-errors >/dev/null

az deployment sub what-if \
  --name "platform-pilot-preview" \
  --location "$LOCATION" \
  --template-file "${INFRA_DIR}/main.bicep" \
  --parameters "$PARAM_FILE" \
  --result-format ResourceIdOnly \
  --no-pretty-print

if [[ "$DEPLOY" != true ]]; then
  echo "Preview complete. Re-run with --apply --confirm DEPLOY to mutate Azure." >&2
  exit 0
fi

[[ "$CONFIRMATION" == "DEPLOY" ]] || {
  echo "Deployment requires --confirm DEPLOY." >&2
  exit 1
}

az deployment sub create \
  --name "platform-pilot" \
  --location "$LOCATION" \
  --template-file "${INFRA_DIR}/main.bicep" \
  --parameters "$PARAM_FILE" \
  --only-show-errors