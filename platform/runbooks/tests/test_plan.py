"""Tests for non-mutating Keycloak planning."""

from platform_runbooks.keycloak.discovery import KeycloakSnapshot
from platform_runbooks.keycloak.plan import (
    ClientExpectation,
    KeycloakExpectation,
    build_plan,
)


def _snapshot() -> KeycloakSnapshot:
    return KeycloakSnapshot(
        realm={"realm": "mcp-gateway"},
        clients=[
            {
                "clientId": "mcp-gateway-m2m",
                "enabled": True,
                "serviceAccountsEnabled": True,
                "standardFlowEnabled": False,
                "directAccessGrantsEnabled": False,
            }
        ],
        groups=["mcp-registry-admin"],
        client_scopes=["mcp-servers-unrestricted/read"],
        oidc_metadata={"issuer": "https://idp.example.test/realms/mcp-gateway"},
    )


def test_plan_is_noop_for_matching_state() -> None:
    expectation = KeycloakExpectation(
        realm="mcp-gateway",
        expected_issuer="https://idp.example.test/realms/mcp-gateway",
        clients=(
            ClientExpectation(
                client_id="mcp-gateway-m2m",
                enabled=True,
                service_accounts_enabled=True,
                standard_flow_enabled=False,
                direct_access_grants_enabled=False,
            ),
        ),
        required_groups=frozenset({"mcp-registry-admin"}),
        required_client_scopes=frozenset({"mcp-servers-unrestricted/read"}),
    )

    plan = build_plan(_snapshot(), expectation)

    assert plan.is_noop


def test_plan_reports_missing_contract_without_secrets() -> None:
    expectation = KeycloakExpectation(
        realm="mcp-gateway",
        clients=(ClientExpectation(client_id="mcp-gateway-web"),),
        required_groups=frozenset({"mcp-registry-user"}),
        required_client_scopes=frozenset({"mcp-servers-restricted/read"}),
    )

    plan = build_plan(_snapshot(), expectation)

    assert not plan.is_noop
    assert {change.path for change in plan.changes} == {
        "groups.mcp-registry-user",
        "clientScopes.mcp-servers-restricted/read",
        "clients.mcp-gateway-web",
    }
    assert all("secret" not in repr(change).lower() for change in plan.changes)
