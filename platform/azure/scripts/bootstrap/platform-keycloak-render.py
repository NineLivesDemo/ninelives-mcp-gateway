#!/usr/bin/env python3
"""Render Keycloak's protected Compose environment file."""

from __future__ import annotations

import json
import os
import pathlib
import tempfile


RAW_SECRETS = pathlib.Path("/etc/platform/secrets/raw")
OUTPUT_PATH = pathlib.Path("/etc/platform/secrets/keycloak.env")


def _read_secret(name: str) -> str:
    value = (RAW_SECRETS / name).read_text(encoding="utf-8")
    value = value.rstrip("\n")
    if not value or "\n" in value or "\r" in value:
        raise ValueError(f"Keycloak secret '{name}' must be one non-empty line.")
    return value


def _write_environment(values: dict[str, str]) -> None:
    content = "".join(f"{name}={json.dumps(value)}\n" for name, value in values.items())
    OUTPUT_PATH.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(
        dir=OUTPUT_PATH.parent,
        prefix=f".{OUTPUT_PATH.name}.",
        text=True,
    )
    temporary_path = pathlib.Path(temporary_name)
    try:
        os.fchmod(file_descriptor, 0o600)
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as output_file:
            output_file.write(content)
            output_file.flush()
            os.fsync(output_file.fileno())
        os.replace(temporary_path, OUTPUT_PATH)
        os.chmod(OUTPUT_PATH, 0o600)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def main() -> None:
    """Render the Keycloak administrator and database credentials."""
    _write_environment(
        {
            "KEYCLOAK_ADMIN_PASSWORD": _read_secret("keycloak-admin-password"),
            "KC_DB_PASSWORD": _read_secret("keycloak-db-password"),
        }
    )


if __name__ == "__main__":
    main()
