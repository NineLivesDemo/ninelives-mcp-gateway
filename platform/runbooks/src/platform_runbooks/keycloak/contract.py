"""MCP Registry Keycloak contract derived from the documented setup flow."""

from __future__ import annotations

from .plan import ClientExpectation, KeycloakExpectation

_REQUIRED_GROUPS = frozenset(
    {
        "a2a-agent-admin",
        "a2a-agent-publisher",
        "a2a-agent-user",
        "mcp-registry-admin",
        "mcp-registry-developer",
        "mcp-registry-operator",
        "mcp-registry-user",
        "mcp-servers-restricted",
        "mcp-servers-unrestricted",
    }
)
_REQUIRED_SCOPES = frozenset(
    {
        "mcp-servers-restricted/execute",
        "mcp-servers-restricted/read",
        "mcp-servers-unrestricted/execute",
        "mcp-servers-unrestricted/read",
    }
)


def _origin(value: str) -> str:
    return value.rstrip("/")


def build_mcp_registry_expectation(
    registry_url: str,
    auth_server_external_url: str,
    keycloak_external_url: str,
    *,
    additional_redirect_uris: frozenset[str] = frozenset(),
    additional_web_origins: frozenset[str] = frozenset(),
) -> KeycloakExpectation:
    """Build the non-secret contract used by the Registry Keycloak setup."""
    registry = _origin(registry_url)
    auth_server = _origin(auth_server_external_url)
    keycloak = _origin(keycloak_external_url)
    redirect_uris = frozenset(
        {
            f"{auth_server}/oauth2/callback/keycloak",
            f"{registry}/*",
            "http://localhost:7860/*",
            "http://localhost:8888/*",
            *additional_redirect_uris,
        }
    )
    web_origins = frozenset({"+", "http://localhost:7860", registry, *additional_web_origins})
    return KeycloakExpectation(
        realm="mcp-gateway",
        expected_issuer=f"{keycloak}/realms/mcp-gateway",
        clients=(
            ClientExpectation(
                client_id="mcp-gateway-web",
                enabled=True,
                standard_flow_enabled=True,
                direct_access_grants_enabled=True,
                redirect_uris=redirect_uris,
                web_origins=web_origins,
                post_logout_redirect_uri=f"{registry}/logout",
            ),
            ClientExpectation(
                client_id="mcp-gateway-m2m",
                enabled=True,
                service_accounts_enabled=True,
                standard_flow_enabled=False,
                direct_access_grants_enabled=False,
            ),
        ),
        required_groups=_REQUIRED_GROUPS,
        required_client_scopes=_REQUIRED_SCOPES,
    )
