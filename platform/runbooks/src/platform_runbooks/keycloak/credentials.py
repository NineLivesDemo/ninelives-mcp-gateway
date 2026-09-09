"""Secret-safe credentials for read-only Keycloak automation."""

from __future__ import annotations

from typing import Any
from urllib.parse import urlparse

import httpx

from .discovery import KeycloakConfigurationError


def _validate_base_url(base_url: str) -> str:
    parsed = urlparse(base_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise KeycloakConfigurationError("Keycloak URL must be an absolute HTTP or HTTPS URL")
    if parsed.username or parsed.password or parsed.fragment:
        raise KeycloakConfigurationError("Keycloak URL must not contain credentials or a fragment")
    return base_url.rstrip("/")


def get_key_vault_secret(
    vault_url: str,
    secret_name: str,
    *,
    credential: Any | None = None,
) -> str:
    """Read one secret with Azure identity without logging its value."""
    if not secret_name or "/" in secret_name:
        raise ValueError("Key Vault secret name must be a simple name")
    if credential is None:
        from azure.identity import DefaultAzureCredential

        credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
    from azure.keyvault.secrets import SecretClient

    client = SecretClient(vault_url=vault_url, credential=credential)
    value = client.get_secret(secret_name).value
    if not value or not value.strip():
        raise ValueError(f"Key Vault secret '{secret_name}' is empty")
    return value.rstrip("\r\n")


def request_admin_token(
    base_url: str,
    username: str,
    password: str,
    *,
    timeout: float = 15.0,
    transport: httpx.BaseTransport | None = None,
) -> str:
    """Exchange Keycloak admin credentials for a short-lived bearer token."""
    if not username or not password:
        raise ValueError("Keycloak admin credentials are required")
    url = f"{_validate_base_url(base_url)}/realms/master/protocol/openid-connect/token"
    with httpx.Client(timeout=timeout, transport=transport) as client:
        response = client.post(
            url,
            data={
                "username": username,
                "password": password,
                "grant_type": "password",
                "client_id": "admin-cli",
            },
        )
    if response.is_error:
        raise httpx.HTTPStatusError(
            f"Keycloak admin token request failed with HTTP {response.status_code}",
            request=response.request,
            response=response,
        )
    payload = response.json()
    token = payload.get("access_token")
    if not isinstance(token, str) or not token:
        raise KeycloakConfigurationError("Keycloak token response did not contain an access token")
    return token


def admin_token_from_key_vault(
    base_url: str,
    username: str,
    vault_url: str,
    password_secret_name: str,
    *,
    credential: Any | None = None,
    timeout: float = 15.0,
    transport: httpx.BaseTransport | None = None,
) -> str:
    """Read the admin password from Key Vault and request a token."""
    password = get_key_vault_secret(
        vault_url,
        password_secret_name,
        credential=credential,
    )
    return request_admin_token(
        base_url,
        username,
        password,
        timeout=timeout,
        transport=transport,
    )
