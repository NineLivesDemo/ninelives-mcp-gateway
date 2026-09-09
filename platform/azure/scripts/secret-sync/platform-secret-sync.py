#!/usr/bin/env python3
"""Render explicitly mapped Azure Key Vault secrets into protected files."""

from __future__ import annotations

import json
import os
import pathlib
import tempfile
import urllib.parse
import urllib.request
from collections.abc import Mapping
from typing import Any

CONFIG_PATH = pathlib.Path("/etc/platform/secret-sync.json")
IMDS_TOKEN_URL = (
    "http://169.254.169.254/metadata/identity/oauth2/token"
    "?api-version=2018-02-01&resource="
    + urllib.parse.quote("https://vault.azure.net/", safe="")
)
KEY_VAULT_API_VERSION = "7.4"
KEY_VAULT_HOST_SUFFIX = ".vault.azure.net"
REQUEST_TIMEOUT_SECONDS = 15
TLS_GROUP_ID = 636
CLOUDFLARED_GROUP_ID = 65532
CLOUDFLARED_TOKEN_PATH = pathlib.Path(
    "/etc/platform/secrets/cloudflare-tunnel-token"
)


def _request_json(
    url: str,
    headers: Mapping[str, str],
) -> dict[str, Any]:
    request = urllib.request.Request(url, headers=dict(headers))
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        payload = json.load(response)
    if not isinstance(payload, dict):
        raise ValueError("The metadata or Key Vault response was not a JSON object.")
    return payload


def _managed_identity_token() -> str:
    payload = _request_json(IMDS_TOKEN_URL, {"Metadata": "true"})
    token = payload.get("access_token")
    if not isinstance(token, str) or not token.strip():
        raise ValueError("The VM managed identity did not return an access token.")
    return token


def _read_secret(
    vault_uri: str,
    secret_name: str,
    access_token: str,
) -> str:
    encoded_name = urllib.parse.quote(secret_name, safe="")
    url = (
        f"{vault_uri.rstrip('/')}/secrets/{encoded_name}"
        f"?api-version={KEY_VAULT_API_VERSION}"
    )
    payload = _request_json(
        url,
        {
            "Authorization": "Bearer " + access_token,
            "Accept": "application/json",
        },
    )
    value = payload.get("value")
    if not isinstance(value, str) or not value:
        raise ValueError(f"Key Vault secret '{secret_name}' was empty or malformed.")
    return value


def _write_secret(path: pathlib.Path, value: str) -> None:
    is_tls_file = path.parent == pathlib.Path("/etc/platform/tls")
    is_cloudflared_token = path == CLOUDFLARED_TOKEN_PATH
    mode = (
        0o640
        if is_cloudflared_token or (is_tls_file and path.suffix == ".key")
        else 0o644
    )
    path.parent.mkdir(mode=0o755 if is_tls_file else 0o750, parents=True, exist_ok=True)
    if is_tls_file:
        os.chmod(path.parent, 0o755)
    file_descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        text=True,
    )
    temporary_path = pathlib.Path(temporary_name)
    try:
        os.fchmod(file_descriptor, mode if is_tls_file else 0o600)
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as secret_file:
            secret_file.write(value)
            secret_file.write("\n")
            secret_file.flush()
            os.fsync(secret_file.fileno())
        os.replace(temporary_path, path)
        if is_tls_file:
            os.chown(path, 0, TLS_GROUP_ID)
        elif is_cloudflared_token:
            os.chown(path, 0, CLOUDFLARED_GROUP_ID)
        os.chmod(path, mode if is_tls_file or is_cloudflared_token else 0o600)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def _load_config() -> tuple[str, list[dict[str, str]]]:
    with CONFIG_PATH.open(encoding="utf-8") as config_file:
        config = json.load(config_file)
    if not isinstance(config, dict):
        raise ValueError("The secret-sync configuration must be a JSON object.")

    vault_uri = config.get("vaultUri")
    mappings = config.get("secrets")
    if not isinstance(vault_uri, str):
        raise ValueError("secret-sync vaultUri must be an HTTPS URL.")
    parsed_vault_uri = urllib.parse.urlsplit(vault_uri)
    if (
        parsed_vault_uri.scheme != "https"
        or parsed_vault_uri.username is not None
        or parsed_vault_uri.password is not None
        or parsed_vault_uri.path not in ("", "/")
        or parsed_vault_uri.query
        or parsed_vault_uri.fragment
        or not parsed_vault_uri.hostname
        or not parsed_vault_uri.hostname.endswith(KEY_VAULT_HOST_SUFFIX)
    ):
        raise ValueError(
            "secret-sync vaultUri must be an HTTPS Azure Key Vault URL."
        )
    try:
        if parsed_vault_uri.port is not None:
            raise ValueError("secret-sync vaultUri must not specify a port.")
    except ValueError as exc:
        raise ValueError("secret-sync vaultUri must not specify a port.") from exc
    if not isinstance(mappings, list) or not mappings:
        raise ValueError("secret-sync must define at least one secret mapping.")

    secrets_root = pathlib.Path("/etc/platform").resolve()
    validated: list[dict[str, str]] = []
    for mapping in mappings:
        if not isinstance(mapping, dict):
            raise ValueError("Each secret-sync mapping must be an object.")
        name = mapping.get("name")
        path = mapping.get("path")
        if not isinstance(name, str) or not name:
            raise ValueError("Each secret-sync mapping requires a secret name.")
        if not isinstance(path, str) or not path.startswith("/etc/platform/"):
            raise ValueError("Secret output paths must remain under /etc/platform/.")
        resolved_path = pathlib.Path(path).resolve(strict=False)
        try:
            resolved_path.relative_to(secrets_root)
        except ValueError as exc:
            raise ValueError(
                "Secret output paths must resolve under /etc/platform/."
            ) from exc
        validated.append({"name": name, "path": str(resolved_path)})
    return vault_uri, validated


def main() -> None:
    vault_uri, mappings = _load_config()
    access_token = _managed_identity_token()
    for mapping in mappings:
        secret_value = _read_secret(vault_uri, mapping["name"], access_token)
        _write_secret(pathlib.Path(mapping["path"]), secret_value)


if __name__ == "__main__":
    main()
