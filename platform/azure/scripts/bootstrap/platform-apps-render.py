#!/usr/bin/env python3
"""Render application dotenv files from explicitly mapped secret files."""

from __future__ import annotations

import json
import os
import pathlib
import tempfile

RAW_ROOT = pathlib.Path("/etc/platform/secrets/raw")
OUTPUT_ROOT = pathlib.Path("/etc/platform/secrets")


def _read_secret(name: str) -> str:
    path = RAW_ROOT / name
    value = path.read_text(encoding="utf-8")
    value = value.rstrip("\r\n")
    if not value:
        raise ValueError(f"Secret file {path} is empty.")
    if name == "auth-server-nginx-marker-secret" and ("\n" in value or "\r" in value):
        raise ValueError(f"Secret file {path} must contain one non-empty line.")
    return value


def _dotenv_line(name: str, value: str) -> str:
    return f"{name}={json.dumps(value)}\n"


def _write_env(name: str, values: dict[str, str]) -> None:
    file_descriptor, temporary_name = tempfile.mkstemp(
        dir=OUTPUT_ROOT,
        prefix=f".{name}.",
        text=True,
    )
    temporary_path = pathlib.Path(temporary_name)
    try:
        os.fchmod(file_descriptor, 0o600)
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as env_file:
            for key, value in values.items():
                env_file.write(_dotenv_line(key, value))
            env_file.flush()
            os.fsync(env_file.fileno())
        os.replace(temporary_path, OUTPUT_ROOT / name)
        os.chmod(OUTPUT_ROOT / name, 0o600)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def main() -> None:
    """Render the Registry and auth-server secret environments."""
    secrets = {
        "SECRET_KEY": _read_secret("registry-secret-key"),
        "AUTH_SERVER_NGINX_MARKER_SECRET": _read_secret(
            "auth-server-nginx-marker-secret"
        ),
        "MONGODB_CONNECTION_STRING": _read_secret("mongodb-connection-string"),
        "KEYCLOAK_CLIENT_SECRET": _read_secret("keycloak-client-secret"),
        "KEYCLOAK_M2M_CLIENT_SECRET": _read_secret("keycloak-m2m-client-secret"),
    }
    registry_secrets = dict(secrets)
    registry_secrets["EMBEDDINGS_API_KEY"] = _read_secret("embeddings-api-key")
    _write_env("registry.env", registry_secrets)
    _write_env("auth-server.env", secrets)


if __name__ == "__main__":
    main()
