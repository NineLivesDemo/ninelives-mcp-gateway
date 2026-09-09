"""Tests for read-only Keycloak discovery."""

import httpx
import pytest
from platform_runbooks.keycloak.discovery import (
    KeycloakAdminClient,
    KeycloakConfigurationError,
)


def test_discover_returns_redacted_snapshot() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/admin/realms/mcp-gateway":
            return httpx.Response(
                200,
                json={
                    "realm": "mcp-gateway",
                    "enabled": True,
                    "smtpServer": {"password": "secret"},
                },
            )
        if request.url.path.endswith("/clients"):
            return httpx.Response(
                200,
                json=[
                    {
                        "clientId": "web",
                        "secret": "hidden",
                        "enabled": True,
                        "redirectUris": ["https://registry.example.test/callback"],
                    }
                ],
            )
        if request.url.path.endswith("/groups"):
            return httpx.Response(
                200,
                json=[{"name": "admins", "subGroups": [{"name": "operators"}]}],
            )
        if request.url.path.endswith("/client-scopes"):
            return httpx.Response(200, json=[{"name": "profile"}])
        if request.url.path.endswith("/.well-known/openid-configuration"):
            return httpx.Response(
                200,
                json={"issuer": "https://idp.example.test/realms/mcp-gateway"},
            )
        return httpx.Response(404)

    with KeycloakAdminClient(
        "https://idp.example.test",
        "mcp-gateway",
        "token",
        transport=httpx.MockTransport(handler),
    ) as client:
        snapshot = client.discover()

    assert snapshot.groups == ["admins", "operators"]
    assert snapshot.client_scopes == ["profile"]
    assert snapshot.clients == [
        {
            "clientId": "web",
            "enabled": True,
            "redirectUris": ["https://registry.example.test/callback"],
        }
    ]
    assert snapshot.realm == {"realm": "mcp-gateway", "enabled": True}


@pytest.mark.parametrize(
    "base_url",
    ["idp.example.test", "ftp://idp.example.test", "https://user:pass@idp.example.test"],
)
def test_rejects_unsafe_keycloak_url(base_url: str) -> None:
    with pytest.raises(KeycloakConfigurationError):
        KeycloakAdminClient(base_url, "mcp-gateway", "token")
