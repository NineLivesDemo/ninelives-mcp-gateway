#!/usr/bin/env bash

set -euo pipefail
umask 077

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    printf 'Usage: %s EMPTY_OUTPUT_DIRECTORY\n' "$0" >&2
    exit 64
fi

OUTPUT_DIR="$(realpath -m "$1")"
mkdir -p "$OUTPUT_DIR"

FIRST_ENTRY="$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)"
if [ -n "$FIRST_ENTRY" ]; then
    printf 'Refusing to write into non-empty directory: %s\n' "$OUTPUT_DIR" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

CA_KEY="$OUTPUT_DIR/platform-ca.key"
CA_CERT="$OUTPUT_DIR/platform-ca.crt"
CA_SERIAL="$WORK_DIR/platform-ca.srl"

openssl req \
    -x509 \
    -newkey rsa:4096 \
    -nodes \
    -keyout "$CA_KEY" \
    -out "$CA_CERT" \
    -days 3650 \
    -sha256 \
    -subj '/CN=MCP Platform Offline CA' \
    -addext 'basicConstraints=critical,CA:TRUE,pathlen:1' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign'

generate_leaf() {
    local name="$1"
    local common_name="$2"
    local extended_key_usage="$3"
    local subject_alt_name="${4:-}"
    local key_path="$OUTPUT_DIR/${name}.key"
    local csr_path="$WORK_DIR/${name}.csr"
    local cert_path="$OUTPUT_DIR/${name}.crt"
    local extensions_path="$WORK_DIR/${name}.ext"

    openssl req \
        -new \
        -newkey rsa:2048 \
        -nodes \
        -keyout "$key_path" \
        -out "$csr_path" \
        -sha256 \
        -subj "/CN=${common_name}"

    temporary_key_path="${WORK_DIR}/${name}.key"
    openssl rsa \
        -traditional \
        -in "$key_path" \
        -out "$temporary_key_path" \
        >/dev/null 2>&1
    mv "$temporary_key_path" "$key_path"

    {
        printf '%s\n' 'basicConstraints=critical,CA:FALSE'
        printf '%s\n' 'keyUsage=critical,digitalSignature,keyEncipherment'
        printf 'extendedKeyUsage=%s\n' "$extended_key_usage"
        if [ -n "$subject_alt_name" ]; then
            printf 'subjectAltName=%s\n' "$subject_alt_name"
        fi
    } >"$extensions_path"

    openssl x509 \
        -req \
        -in "$csr_path" \
        -CA "$CA_CERT" \
        -CAkey "$CA_KEY" \
        -CAserial "$CA_SERIAL" \
        -CAcreateserial \
        -out "$cert_path" \
        -days 825 \
        -sha256 \
        -extfile "$extensions_path"
}

generate_leaf \
    'etcd-server' \
    'etcd.platform.internal' \
    'serverAuth' \
    'DNS:etcd.platform.internal,IP:10.60.2.4'

generate_leaf \
    'etcd-edge-client' \
    'apisix-edge' \
    'clientAuth'

generate_leaf \
    'etcd-health-client' \
    'etcd-health-check' \
    'clientAuth'

generate_leaf \
    'openbao-tls' \
    'openbao.platform.internal' \
    'serverAuth' \
    'DNS:openbao.platform.internal,IP:10.60.3.4'

chmod 600 "$OUTPUT_DIR"/*.key
chmod 644 "$OUTPUT_DIR"/*.crt

printf 'Generated platform certificates in %s\n' "$OUTPUT_DIR"
printf 'Keep platform-ca.key offline; seed only the mapped certificates and leaf keys.\n'
