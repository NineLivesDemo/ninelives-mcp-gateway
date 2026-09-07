#!/bin/sh

set -eu

ADMIN_URL="http://apisix:9180/apisix/admin/routes/registry"
ROUTE_FILE="/config/registry-route.json"

if [ -z "${APISIX_ADMIN_KEY:-}" ]; then
    echo "APISIX_ADMIN_KEY must be set" >&2
    exit 1
fi

if [ "${#APISIX_ADMIN_KEY}" -lt 32 ]; then
    echo "APISIX_ADMIN_KEY must contain at least 32 characters" >&2
    exit 1
fi

case "$APISIX_ADMIN_KEY" in
    *[!A-Za-z0-9_-]*)
        echo "APISIX_ADMIN_KEY contains unsupported characters" >&2
        exit 1
        ;;
esac

curl_config="$(mktemp)"
chmod 600 "$curl_config"
printf 'header = "X-API-KEY: %s"\n' "$APISIX_ADMIN_KEY" > "$curl_config"

admin_request() {
    curl --config "$curl_config" --silent --show-error "$@"
}

response_file="$(mktemp)"
chmod 600 "$response_file"
trap 'rm -f "$curl_config" "$response_file"' EXIT

for _attempt in $(seq 1 30); do
    if status="$(
        admin_request \
            --connect-timeout 2 \
            --max-time 5 \
            --output "$response_file" \
            --write-out "%{http_code}" \
            "$ADMIN_URL" 2>/dev/null
    )"; then
        case "$status" in
            200)
                exit 0
                ;;
            404)
                break
                ;;
            401)
                echo "APISIX Admin API rejected APISIX_ADMIN_KEY" >&2
                exit 1
                ;;
        esac
    fi
    sleep 1
done

if [ "${status:-000}" != "404" ]; then
    echo "APISIX Admin API did not become ready" >&2
    exit 1
fi

status="$(
    admin_request \
        --request PUT \
        --header "Content-Type: application/json" \
        --data-binary "@$ROUTE_FILE" \
        --write-out "%{http_code}" \
        --output "$response_file" \
        "$ADMIN_URL"
)"

case "$status" in
    200|201)
        exit 0
        ;;
    *)
        echo "APISIX Registry route bootstrap failed with HTTP status $status" >&2
        exit 1
        ;;
esac
