"""Read-only Keycloak discovery for Azure platform automation.

The application contract remains documented under ``docs/``. This module only
observes the current Keycloak state; it never creates realms, clients, users,
groups, scopes, or secrets.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any
from urllib.parse import quote, urlparse

import httpx


class KeycloakConfigurationError(ValueError):
    """Raised when a Keycloak endpoint or response is invalid."""


def _validate_base_url(base_url: str) -> str:
    parsed = urlparse(base_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise KeycloakConfigurationError("Keycloak URL must be an absolute HTTP or HTTPS URL")
    if parsed.username or parsed.password or parsed.fragment:
        raise KeycloakConfigurationError("Keycloak URL must not contain credentials or a fragment")
    return base_url.rstrip("/")


def _flatten_groups(groups: list[dict[str, Any]]) -> list[str]:
    names: list[str] = []
    for group in groups:
        name = group.get("name")
        if isinstance(name, str) and name:
            names.append(name)
        children = group.get("subGroups", [])
        if isinstance(children, list):
            names.extend(_flatten_groups(children))
    return sorted(set(names))


def _project_client(client: dict[str, Any]) -> dict[str, Any]:
    fields = (
        "clientId",
        "name",
        "enabled",
        "protocol",
        "publicClient",
        "standardFlowEnabled",
        "implicitFlowEnabled",
        "directAccessGrantsEnabled",
        "serviceAccountsEnabled",
        "redirectUris",
        "webOrigins",
    )
    projected = {field: client[field] for field in fields if field in client}
    attributes = client.get("attributes")
    if isinstance(attributes, dict):
        safe_attributes = {
            name: attributes[name]
            for name in ("post.logout.redirect.uris", "oauth2.device.authorization.grant.enabled")
            if name in attributes
        }
        if safe_attributes:
            projected["attributes"] = safe_attributes
    return projected


def _project_realm(realm: dict[str, Any]) -> dict[str, Any]:
    fields = (
        "realm",
        "enabled",
        "registrationAllowed",
        "loginWithEmailAllowed",
        "duplicateEmailsAllowed",
        "resetPasswordAllowed",
        "editUsernameAllowed",
        "sslRequired",
        "defaultSignatureAlgorithm",
        "accessTokenLifespan",
    )
    return {field: realm[field] for field in fields if field in realm}


@dataclass(frozen=True)
class KeycloakSnapshot:
    """Redacted state discovered from one Keycloak realm."""

    realm: dict[str, Any]
    clients: list[dict[str, Any]]
    groups: list[str]
    client_scopes: list[str]
    oidc_metadata: dict[str, Any]


class KeycloakAdminClient:
    """Read-only client for the Keycloak Admin and OIDC APIs."""

    def __init__(
        self,
        base_url: str,
        realm: str,
        admin_token: str,
        *,
        timeout: float = 15.0,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        if not realm or "/" in realm:
            raise KeycloakConfigurationError("Keycloak realm must be a simple name")
        if not admin_token.strip():
            raise KeycloakConfigurationError("Keycloak admin token is required")
        self._realm = realm
        self._client = httpx.Client(
            base_url=_validate_base_url(base_url),
            headers={"Authorization": f"Bearer {admin_token}"},
            timeout=timeout,
            transport=transport,
        )

    def close(self) -> None:
        """Close the underlying HTTP client."""
        self._client.close()

    def __enter__(self) -> KeycloakAdminClient:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def _get(self, path: str) -> Any:
        response = self._client.get(path)
        if response.is_error:
            raise httpx.HTTPStatusError(
                f"Keycloak returned HTTP {response.status_code} for a read-only request",
                request=response.request,
                response=response,
            )
        return response.json()

    def discover(self) -> KeycloakSnapshot:
        """Read and redact the current realm configuration without mutation."""
        realm_path = f"/admin/realms/{quote(self._realm, safe='')}"
        clients = self._get(f"{realm_path}/clients?max=1000")
        groups = self._get(f"{realm_path}/groups?briefRepresentation=false&max=1000")
        scopes = self._get(f"{realm_path}/client-scopes?max=1000")
        realm = self._get(realm_path)
        metadata = self._get(
            f"/realms/{quote(self._realm, safe='')}/.well-known/openid-configuration"
        )

        if not isinstance(realm, dict):
            raise KeycloakConfigurationError("Keycloak realm response was not an object")
        if not isinstance(clients, list) or not all(isinstance(item, dict) for item in clients):
            raise KeycloakConfigurationError("Keycloak client response was not a list")
        if not isinstance(groups, list) or not all(isinstance(item, dict) for item in groups):
            raise KeycloakConfigurationError("Keycloak group response was not a list")
        if not isinstance(scopes, list) or not all(isinstance(item, dict) for item in scopes):
            raise KeycloakConfigurationError("Keycloak scope response was not a list")
        if not isinstance(metadata, dict):
            raise KeycloakConfigurationError("OIDC metadata response was not an object")

        return KeycloakSnapshot(
            realm=_project_realm(realm),
            clients=sorted(
                (_project_client(client) for client in clients),
                key=lambda client: client.get("clientId", ""),
            ),
            groups=_flatten_groups(groups),
            client_scopes=sorted(
                scope["name"]
                for scope in scopes
                if isinstance(scope.get("name"), str) and scope["name"]
            ),
            oidc_metadata=metadata,
        )
