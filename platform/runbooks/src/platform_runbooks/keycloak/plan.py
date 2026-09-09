"""Non-mutating Keycloak desired-state planning."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .discovery import KeycloakSnapshot


@dataclass(frozen=True)
class ClientExpectation:
    """Non-secret configuration required for one Keycloak client."""

    client_id: str
    enabled: bool | None = None
    service_accounts_enabled: bool | None = None
    standard_flow_enabled: bool | None = None
    direct_access_grants_enabled: bool | None = None
    redirect_uris: frozenset[str] = frozenset()
    web_origins: frozenset[str] = frozenset()
    post_logout_redirect_uri: str | None = None


@dataclass(frozen=True)
class KeycloakExpectation:
    """Documented, non-secret MCP Registry Keycloak contract."""

    realm: str
    clients: tuple[ClientExpectation, ...]
    required_groups: frozenset[str]
    required_client_scopes: frozenset[str]
    expected_issuer: str | None = None


@dataclass(frozen=True)
class PlanChange:
    """One non-secret desired-state difference."""

    path: str
    expected: Any
    actual: Any


@dataclass(frozen=True)
class KeycloakPlan:
    """Deterministic read-only plan result."""

    changes: tuple[PlanChange, ...]
    warnings: tuple[str, ...]

    @property
    def is_noop(self) -> bool:
        """Return whether the live state matches the expectation."""
        return not self.changes


def _client_map(snapshot: KeycloakSnapshot) -> dict[str, dict[str, Any]]:
    return {
        client["clientId"]: client
        for client in snapshot.clients
        if isinstance(client.get("clientId"), str)
    }


def _compare_client(
    client: ClientExpectation,
    actual: dict[str, Any] | None,
) -> list[PlanChange]:
    if actual is None:
        return [PlanChange(f"clients.{client.client_id}", "present", "missing")]

    changes: list[PlanChange] = []
    checks = {
        "enabled": client.enabled,
        "serviceAccountsEnabled": client.service_accounts_enabled,
        "standardFlowEnabled": client.standard_flow_enabled,
        "directAccessGrantsEnabled": client.direct_access_grants_enabled,
    }
    for field, expected in checks.items():
        if expected is not None and actual.get(field) != expected:
            changes.append(
                PlanChange(f"clients.{client.client_id}.{field}", expected, actual.get(field))
            )

    if client.redirect_uris:
        actual_uris = frozenset(actual.get("redirectUris", []))
        if actual_uris != client.redirect_uris:
            changes.append(
                PlanChange(
                    f"clients.{client.client_id}.redirectUris",
                    sorted(client.redirect_uris),
                    sorted(actual_uris),
                )
            )
    if client.web_origins:
        actual_origins = frozenset(actual.get("webOrigins", []))
        if actual_origins != client.web_origins:
            changes.append(
                PlanChange(
                    f"clients.{client.client_id}.webOrigins",
                    sorted(client.web_origins),
                    sorted(actual_origins),
                )
            )
    if client.post_logout_redirect_uri is not None:
        actual_attributes = actual.get("attributes", {})
        actual_logout = actual_attributes.get("post.logout.redirect.uris")
        if actual_logout != client.post_logout_redirect_uri:
            changes.append(
                PlanChange(
                    f"clients.{client.client_id}.post.logout.redirect.uris",
                    client.post_logout_redirect_uri,
                    actual_logout,
                )
            )
    return changes


def build_plan(
    snapshot: KeycloakSnapshot,
    expectation: KeycloakExpectation,
) -> KeycloakPlan:
    """Compare a live snapshot with the documented non-secret contract."""
    changes: list[PlanChange] = []
    warnings: list[str] = []

    if snapshot.realm.get("realm") != expectation.realm:
        changes.append(PlanChange("realm", expectation.realm, snapshot.realm.get("realm")))
    if expectation.expected_issuer is not None:
        actual_issuer = snapshot.oidc_metadata.get("issuer")
        if actual_issuer != expectation.expected_issuer:
            changes.append(PlanChange("oidc.issuer", expectation.expected_issuer, actual_issuer))

    actual_groups = frozenset(snapshot.groups)
    for group in sorted(expectation.required_groups - actual_groups):
        changes.append(PlanChange(f"groups.{group}", "present", "missing"))

    actual_scopes = frozenset(snapshot.client_scopes)
    for scope in sorted(expectation.required_client_scopes - actual_scopes):
        changes.append(PlanChange(f"clientScopes.{scope}", "present", "missing"))

    clients = _client_map(snapshot)
    for client in expectation.clients:
        changes.extend(_compare_client(client, clients.get(client.client_id)))

    expected_client_ids = {client.client_id for client in expectation.clients}
    unexpected = sorted(set(clients) - expected_client_ids)
    if unexpected:
        warnings.append(
            "Unmanaged clients exist; review before removing them: " + ", ".join(unexpected)
        )
    return KeycloakPlan(tuple(changes), tuple(warnings))
