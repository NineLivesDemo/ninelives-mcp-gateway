#!/bin/sh

set -eu

BAO_ADDR="http://127.0.0.1:8200"
CONFIG_DIR="/openbao/config"
DATA_DIR="/openbao/data"
BOOTSTRAP_DIR="/openbao/bootstrap"
CLIENT_DIR="/openbao/client"
UNSEAL_KEY_FILE="${BOOTSTRAP_DIR}/unseal_key"
ROOT_TOKEN_FILE="${BOOTSTRAP_DIR}/root_token"
CLIENT_TOKEN_FILE="${CLIENT_DIR}/client_token"
POLICY_NAME="mcp-egress"
POLICY_PATH="/tmp/${POLICY_NAME}.hcl"
UNSEAL_PAYLOAD_FILE="/tmp/openbao-unseal.json"

umask 077
mkdir -p "$DATA_DIR" "$BOOTSTRAP_DIR" "$CLIENT_DIR"
chown openbao:openbao "$DATA_DIR" "$BOOTSTRAP_DIR" "$CLIENT_DIR"

# Move credentials created by earlier local versions out of the registry mount.
if [ ! -s "$UNSEAL_KEY_FILE" ] && [ -s "${CLIENT_DIR}/unseal_key" ]; then
  mv "${CLIENT_DIR}/unseal_key" "$UNSEAL_KEY_FILE"
fi
if [ ! -s "$ROOT_TOKEN_FILE" ] && [ -s "${CLIENT_DIR}/root_token" ]; then
  mv "${CLIENT_DIR}/root_token" "$ROOT_TOKEN_FILE"
fi

su-exec openbao bao server -config="$CONFIG_DIR" &
server_pid=$!

cleanup() {
  rm -f "$POLICY_PATH" "$UNSEAL_PAYLOAD_FILE"
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

status_json=""
for _ in $(seq 1 60); do
  status_json="$(bao status -address="$BAO_ADDR" -format=json 2>/dev/null || true)"
  if [ -n "$status_json" ]; then
    break
  fi
  sleep 1
done

if [ -z "$status_json" ]; then
  echo "OpenBao did not become ready." >&2
  exit 1
fi

if printf '%s' "$status_json" | grep -q '"initialized"[[:space:]]*:[[:space:]]*false'; then
  init_json="$(bao operator init \
    -address="$BAO_ADDR" \
    -format=json \
    -key-shares=1 \
    -key-threshold=1 \
    -non-interactive)"
  unseal_key="$(printf '%s' "$init_json" | sed -n \
    '/"unseal_keys_b64"/{n;s/^[[:space:]]*"\([^"]*\)".*/\1/p;}')"
  root_token="$(printf '%s' "$init_json" | sed -n \
    's/.*"root_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

  if [ -z "$unseal_key" ] || [ -z "$root_token" ]; then
    echo "OpenBao initialization returned incomplete credentials." >&2
    exit 1
  fi

  printf '%s\n' "$unseal_key" > "${UNSEAL_KEY_FILE}.tmp"
  mv "${UNSEAL_KEY_FILE}.tmp" "$UNSEAL_KEY_FILE"
  chown openbao:openbao "$UNSEAL_KEY_FILE"
  chmod 600 "$UNSEAL_KEY_FILE"

  printf '%s\n' "$root_token" > "${ROOT_TOKEN_FILE}.tmp"
  mv "${ROOT_TOKEN_FILE}.tmp" "$ROOT_TOKEN_FILE"
  chown openbao:openbao "$ROOT_TOKEN_FILE"
  chmod 600 "$ROOT_TOKEN_FILE"
else
  if [ ! -s "$UNSEAL_KEY_FILE" ]; then
    echo "OpenBao is initialized but the local unseal key is missing." >&2
    exit 1
  fi
  unseal_key="$(sed -n '1p' "$UNSEAL_KEY_FILE")"
  root_token=""
  if [ -s "$ROOT_TOKEN_FILE" ]; then
    root_token="$(sed -n '1p' "$ROOT_TOKEN_FILE")"
  fi
fi

if printf '%s' "$status_json" | grep -q '"sealed"[[:space:]]*:[[:space:]]*true'; then
  printf '{"key":"%s"}\n' "$unseal_key" > "$UNSEAL_PAYLOAD_FILE"
  if ! wget -q -O /dev/null \
    --header="Content-Type: application/json" \
    --post-file="$UNSEAL_PAYLOAD_FILE" \
    "${BAO_ADDR}/v1/sys/unseal"; then
    echo "OpenBao unseal request failed during local bootstrap." >&2
    exit 1
  fi
  rm -f "$UNSEAL_PAYLOAD_FILE"
fi

status_json="$(bao status -address="$BAO_ADDR" -format=json 2>/dev/null || true)"
if printf '%s' "$status_json" | grep -q '"sealed"[[:space:]]*:[[:space:]]*true'; then
  echo "OpenBao remains sealed after local bootstrap." >&2
  exit 1
fi

if [ ! -s "$CLIENT_TOKEN_FILE" ]; then
  if [ -z "$root_token" ]; then
    echo "OpenBao client token is missing and the local root token is unavailable." >&2
    exit 1
  fi

  cat > "$POLICY_PATH" <<EOF
path "${OPENBAO_KV_MOUNT:-secret}/data/mcp/egress/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "${OPENBAO_KV_MOUNT:-secret}/metadata/mcp/egress/*" {
  capabilities = ["read", "list", "delete"]
}
EOF
  kv_mount="${OPENBAO_KV_MOUNT:-secret}"
  if ! mounts_json="$(BAO_TOKEN="$root_token" bao secrets list \
    -address="$BAO_ADDR" \
    -format=json 2>/dev/null)"; then
    echo "OpenBao mount listing failed during local bootstrap." >&2
    exit 1
  fi
  if ! printf '%s' "$mounts_json" | grep -q "\"${kv_mount}/\""; then
    BAO_TOKEN="$root_token" bao secrets enable \
      -address="$BAO_ADDR" \
      -path="$kv_mount" \
      kv-v2 >/dev/null
  fi
  BAO_TOKEN="$root_token" bao policy write \
    -address="$BAO_ADDR" \
    "$POLICY_NAME" "$POLICY_PATH" >/dev/null
  client_token_json="$(BAO_TOKEN="$root_token" bao token create \
    -address="$BAO_ADDR" \
    -format=json \
    -orphan \
    -no-default-policy \
    -policy="$POLICY_NAME" \
    -period=768h)"
  client_token="$(printf '%s' "$client_token_json" | awk -F'"' '/"client_token"/ { print $4; exit }')"
  rm -f "$POLICY_PATH"

  if [ -z "$client_token" ]; then
    echo "OpenBao client token creation returned no token." >&2
    exit 1
  fi

  printf '%s\n' "$client_token" > "${CLIENT_TOKEN_FILE}.tmp"
  mv "${CLIENT_TOKEN_FILE}.tmp" "$CLIENT_TOKEN_FILE"
  chown openbao:openbao "$CLIENT_TOKEN_FILE"
  chmod 640 "$CLIENT_TOKEN_FILE"
fi

echo "OpenBao is initialized, unsealed, and ready with persistent file storage."
wait "$server_pid"
