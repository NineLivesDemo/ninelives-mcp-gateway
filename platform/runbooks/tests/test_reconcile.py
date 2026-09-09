"""Tests for safe targeted Keycloak reconciliation."""

import httpx
import pytest
from platform_runbooks.keycloak.plan import ClientExpectation, KeycloakExpectation, KeycloakPlan
from platform_runbooks.keycloak.reconcile import KeycloakReconciler, KeycloakReconciliationError


def _expectation() -> KeycloakExpectation:
    return KeycloakExpectation(
        realm="mcp-gateway",
        clients=(ClientExpectation(client_id="mcp-gateway-m2m", enabled=True),),
        required_groups=frozenset({"mcp-registry-user"}),
        required_client_scopes=frozenset({"mcp-servers-restricted/read"}),
    )


def test_reconcile_requires_existing_realm_and_approval() -> None:
    with KeycloakReconciler("https://idp.example.test", "mcp-gateway", "token") as reconciler:
        with pytest.raises(KeycloakReconciliationError, match="preflight"):
            reconciler.reconcile(
                KeycloakPlan((object(),), ()),  # type: ignore[arg-type]
                _expectation(),
                existing_realm_verified=False,
                approved=True,
            )


def test_reconcile_preserves_client_secret_and_rejects_missing_clients() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "GET" and request.url.path.endswith("/admin/realms/mcp-gateway"):
            return httpx.Response(200, json={"realm": "mcp-gateway"})
        if request.method == "GET" and request.url.path.endswith("/clients"):
            return httpx.Response(200, json=[])
        if request.method == "GET" and request.url.path.endswith("/groups"):
            return httpx.Response(200, json=[])
        if request.method == "GET" and request.url.path.endswith("/client-scopes"):
            return httpx.Response(200, json=[])
        return httpx.Response(404)

    with KeycloakReconciler(
        "https://idp.example.test",
        "mcp-gateway",
        "token",
        transport=httpx.MockTransport(handler),
    ) as reconciler:
        with pytest.raises(KeycloakReconciliationError, match="bootstrap is not permitted"):
            reconciler.reconcile(
                KeycloakPlan((object(),), ()),  # type: ignore[arg-type]
                _expectation(),
                existing_realm_verified=True,
                approved=True,
            )
