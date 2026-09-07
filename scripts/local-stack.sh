#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BASE_COMPOSE_FILE="docker-compose.prebuilt.yml"
EDGE_COMPOSE_FILE="docker-compose.edge.yml"

usage() {
    cat <<'EOF'
Usage: scripts/local-stack.sh <command> [options]

Commands:
  start       Start the prebuilt local stack
  stop        Stop and remove all local containers without removing volumes
  status      Show local container status

Options for start:
  --debug     Also start local Prometheus and Grafana
EOF
}

compose_base() {
    docker compose -f "$BASE_COMPOSE_FILE" "$@"
}

stop_stack() {
    compose_base --profile debug-observability down --remove-orphans
}

edge_configuration_available() {
    [[ -n "${APISIX_ADMIN_KEY:-}" ]] ||
        grep -Eq '^APISIX_ADMIN_KEY=[^[:space:]]+' "$PROJECT_ROOT/.env" 2>/dev/null
}

start_stack() {
    local debug=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug)
                debug=true
                ;;
            *)
                echo "Unknown start option: $1" >&2
                usage >&2
                exit 2
                ;;
        esac
        shift
    done

    if ! edge_configuration_available; then
        echo "APISIX_ADMIN_KEY must be set before starting the local stack." >&2
        exit 1
    fi

    "$PROJECT_ROOT/build_and_run.sh" --prebuilt

    local compose_args=(-f "$BASE_COMPOSE_FILE" -f "$EDGE_COMPOSE_FILE")
    local profile_args=(--profile edge)

    if [[ "$debug" == true ]]; then
        profile_args+=(--profile debug-observability)
    fi

    (
        cd "$PROJECT_ROOT"
        docker compose "${compose_args[@]}" "${profile_args[@]}" up -d
    )
}

main() {
    if [[ $# -eq 0 ]]; then
        usage >&2
        exit 2
    fi

    local command="$1"
    shift

    cd "$PROJECT_ROOT"

    case "$command" in
        start)
            start_stack "$@"
            ;;
        stop)
            [[ $# -eq 0 ]] || {
                echo "The stop command does not accept options." >&2
                usage >&2
                exit 2
            }
            stop_stack
            ;;
        status)
            [[ $# -eq 0 ]] || {
                echo "The status command does not accept options." >&2
                usage >&2
                exit 2
            }
            if edge_configuration_available; then
                docker compose \
                    -f "$BASE_COMPOSE_FILE" \
                    -f "$EDGE_COMPOSE_FILE" \
                    --profile edge \
                    --profile debug-observability \
                    ps
            else
                compose_base --profile debug-observability ps
                docker ps -a \
                    --filter "name=^mcp-apisix-etcd$" \
                    --filter "name=^mcp-apisix-bootstrap$" \
                    --format 'table {{.Names}}\t{{.Status}}'
            fi
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo "Unknown command: $command" >&2
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
