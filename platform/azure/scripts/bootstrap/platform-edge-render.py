#!/usr/bin/env python3
"""Render the edge Compose environment and APISIX route from protected inputs."""

from __future__ import annotations

import json
import os
import pathlib
import re
import tempfile

EDGE_ENV_PATH = pathlib.Path("/etc/platform/secrets/edge.env")
ORIGIN_CONFIG_PATH = pathlib.Path("/etc/platform/config/edge-origin.env")
REGISTRY_ROUTE_TEMPLATE_PATH = pathlib.Path(
    "/opt/platform/compose/edge/registry-route.template.json"
)
REGISTRY_ROUTE_PATH = pathlib.Path("/opt/platform/compose/edge/registry-route.json")
KEYCLOAK_ROUTE_TEMPLATE_PATH = pathlib.Path(
    "/opt/platform/compose/edge/keycloak-route.template.json"
)
KEYCLOAK_ROUTE_PATH = pathlib.Path("/opt/platform/compose/edge/keycloak-route.json")
ADMIN_KEY_PATH = pathlib.Path("/etc/platform/secrets/apisix-admin-key")
HOST_PATTERN = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$")
SCHEME_PATTERN = re.compile(r"^(?:http|https)$")
PORT_PATTERN = re.compile(r"^[1-9][0-9]{0,4}$")
ADMIN_KEY_PATTERN = re.compile(r"^[A-Za-z0-9_-]{32,}$")


def _read_single_line(path: pathlib.Path) -> str:
    value = path.read_text(encoding="utf-8")
    if value.endswith("\n"):
        value = value[:-1]
    if not value or "\n" in value or "\r" in value or value.strip() != value:
        raise ValueError(f"{path} must contain exactly one non-empty line.")
    return value


def _load_origin_config() -> dict[str, str]:
    values: dict[str, str] = {}
    allowed = {
        "KEYCLOAK_HOST_HEADER",
        "KEYCLOAK_ORIGIN_HOST",
        "KEYCLOAK_ORIGIN_PORT",
        "KEYCLOAK_ORIGIN_SCHEME",
        "REGISTRY_HOST_HEADER",
        "REGISTRY_ORIGIN_HOST",
        "REGISTRY_ORIGIN_PORT",
        "REGISTRY_ORIGIN_SCHEME",
    }
    for raw_line in ORIGIN_CONFIG_PATH.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or key not in allowed or not value or key in values:
            raise ValueError(f"Invalid edge origin configuration line in {ORIGIN_CONFIG_PATH}.")
        values[key] = value

    if set(values) != allowed:
        raise ValueError(
            "edge-origin.env must define both origin hosts, schemes, ports, and host headers."
        )
    for key in ("KEYCLOAK_HOST_HEADER", "KEYCLOAK_ORIGIN_HOST",
                "REGISTRY_HOST_HEADER", "REGISTRY_ORIGIN_HOST"):
        if not HOST_PATTERN.fullmatch(values[key]) or ".." in values[key]:
            raise ValueError(f"{key} is not a valid DNS host name or address.")
    for key in ("KEYCLOAK_ORIGIN_SCHEME", "REGISTRY_ORIGIN_SCHEME"):
        if not SCHEME_PATTERN.fullmatch(values[key]):
            raise ValueError(f"{key} must be either http or https.")
    for key in ("KEYCLOAK_ORIGIN_PORT", "REGISTRY_ORIGIN_PORT"):
        if not PORT_PATTERN.fullmatch(values[key]) or int(values[key]) > 65535:
            raise ValueError(f"{key} must be a valid TCP port.")
    return values


def _atomic_write(path: pathlib.Path, content: str, mode: int) -> None:
    path.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        text=True,
    )
    temporary_path = pathlib.Path(temporary_name)
    try:
        os.fchmod(file_descriptor, mode)
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as output_file:
            output_file.write(content)
            output_file.flush()
            os.fsync(output_file.fileno())
        os.replace(temporary_path, path)
        os.chmod(path, mode)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def _render_edge_environment(admin_key: str) -> None:
    if not ADMIN_KEY_PATTERN.fullmatch(admin_key):
        raise ValueError(
            "APISIX_ADMIN_KEY must contain at least 32 alphanumeric, underscore, or hyphen characters."
        )
    _atomic_write(
        EDGE_ENV_PATH,
        f"APISIX_ADMIN_KEY='{admin_key}'\n",
        0o600,
    )


def _render_registry_route(origin: dict[str, str]) -> None:
    route = json.loads(REGISTRY_ROUTE_TEMPLATE_PATH.read_text(encoding="utf-8"))
    upstream = route.get("upstream")
    if not isinstance(upstream, dict):
        raise ValueError("The APISIX route template has no upstream object.")
    upstream["scheme"] = origin["REGISTRY_ORIGIN_SCHEME"]
    upstream["upstream_host"] = origin["REGISTRY_HOST_HEADER"]
    upstream["nodes"] = {
        f"{origin['REGISTRY_ORIGIN_HOST']}:{origin['REGISTRY_ORIGIN_PORT']}": 1
    }
    plugins = route.get("plugins")
    proxy_rewrite = plugins.get("proxy-rewrite") if isinstance(plugins, dict) else None
    headers = proxy_rewrite.get("headers") if isinstance(proxy_rewrite, dict) else None
    forwarded_headers = headers.get("set") if isinstance(headers, dict) else None
    if not isinstance(forwarded_headers, dict):
        raise ValueError("The Registry route template has no proxy-rewrite headers.")
    forwarded_headers["X-Forwarded-Host"] = origin["REGISTRY_HOST_HEADER"]
    _atomic_write(REGISTRY_ROUTE_PATH, json.dumps(route, indent=2) + "\n", 0o644)


def _render_keycloak_route(origin: dict[str, str]) -> None:
    route = json.loads(KEYCLOAK_ROUTE_TEMPLATE_PATH.read_text(encoding="utf-8"))
    upstream = route.get("upstream")
    if not isinstance(upstream, dict):
        raise ValueError("The Keycloak route template has no upstream object.")
    upstream["scheme"] = origin["KEYCLOAK_ORIGIN_SCHEME"]
    upstream["upstream_host"] = origin["KEYCLOAK_ORIGIN_HOST"]
    upstream["nodes"] = {
        f"{origin['KEYCLOAK_ORIGIN_HOST']}:{origin['KEYCLOAK_ORIGIN_PORT']}": 1
    }
    _atomic_write(KEYCLOAK_ROUTE_PATH, json.dumps(route, indent=2) + "\n", 0o644)


def main() -> None:
    """Render the protected edge environment and the APISIX Registry route."""
    origin = _load_origin_config()
    _render_edge_environment(_read_single_line(ADMIN_KEY_PATH))
    _render_registry_route(origin)
    _render_keycloak_route(origin)


if __name__ == "__main__":
    main()
