"""Approval-gated, targeted Keycloak reconciliation for an existing realm."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any
from urllib.parse import quote

import httpx

from .discovery import KeycloakConfigurationError
from .plan import ClientExpectation, KeycloakExpectation, KeycloakPlan


class KeycloakReconciliationError(RuntimeError):
    """Raised when safe targeted reconciliation cannot proceed."""


@dataclass(frozen=True)
class ReconcileResult:
    """Redacted result of an approved targeted reconciliation."""

    updated_clients: tuple[str, ...]
    created_groups: tuple[str, ...]
    created_scopes: tuple[str, ...]


class KeycloakReconciler:
    """Mutate only existing-realm non-secret configuration."""

    def __init__(
        self,
        base_url: str,
        realm: str,
        admin_token: str,
        *,
        timeout: float = 15.0,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        if not admin_token.strip():
            raise KeycloakConfigurationError("Keycloak admin token is required")
        self._realm = quote(realm, safe="")
        self._client = httpx.Client(
            base_url=base_url.rstrip("/"),
            headers={"Authorization": "******"},
            timeout=timeout,
            transport=transport,
        )

    def __enter__(self) -> KeycloakReconciler:
        return self

    def __exit__(self, *_: object) -> None:
        self._client.close()

    def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        response = self._client.request(method, path, **kwargs)
        if response.is_error:
            raise KeycloakReconciliationError(
                f"Keycloak returned HTTP {response.status_code} for targeted reconciliation"
            )
        if not response.content:
            return None
        return response.json()

    def reconcile(
        self,
        plan: KeycloakPlan,
        expectation: KeycloakExpectation,
        *,
        existing_realm_verified: bool,
        approved: bool,
    ) -> ReconcileResult:
        """Apply only approved, non-secret changes to an existing realm."""
        if not existing_realm_verified:
            raise KeycloakReconciliationError("Existing-realm preflight is required")
        if not approved:
            raise KeycloakReconciliationError("Explicit reconciliation approval is required")
        if plan.is_noop:
            return ReconcileResult((), (), ())

        realm_path = f"/admin/realms/{self._realm}"
        realm = self._request("GET", realm_path)
        if not isinstance(realm, dict) or realm.get("realm") != expectation.realm:
            raise KeycloakReconciliationError("Existing realm preflight does not match expectation")

        clients = self._request("GET", f"{realm_path}/clients?max=1000")
        groups = self._request("GET", f"{realm_path}/groups?max=1000")
        scopes = self._request("GET", f"{realm_path}/client-scopes?max=1000")
        if not all(isinstance(items, list) for items in (clients, groups, scopes)):
            raise KeycloakReconciliationError("Keycloak returned an invalid reconciliation state")

        client_map = {item.get("clientId"): item for item in clients if isinstance(item, dict)}
        updated_clients = self._update_clients(realm_path, expectation.clients, client_map)
        existing_groups = {item.get("name") for item in groups if isinstance(item, dict)}
        created_groups = self._create_groups(
            realm_path, expectation.required_groups - existing_groups
        )
        existing_scopes = {item.get("name") for item in scopes if isinstance(item, dict)}
        created_scopes = self._create_scopes(
            realm_path,
            expectation.required_client_scopes - existing_scopes,
        )
        return ReconcileResult(updated_clients, created_groups, created_scopes)

    def _update_clients(
        self,
        realm_path: str,
        expectations: tuple[ClientExpectation, ...],
        clients: dict[str, dict[str, Any]],
    ) -> tuple[str, ...]:
        updated: list[str] = []
        for expected in expectations:
            current = clients.get(expected.client_id)
            if not current or not isinstance(current.get("id"), str):
                raise KeycloakReconciliationError(
                    f"Client '{expected.client_id}' is missing; bootstrap is not permitted"
                )
            payload = {
                key: value
                for key, value in current.items()
                if key not in {"secret", "clientSecret", "id"}
            }
            _apply_client_expectation(payload, expected)
            self._request(
                "PUT", f"{realm_path}/clients/{quote(current['id'], safe='')}", json=payload
            )
            updated.append(expected.client_id)
        return tuple(updated)

    def _create_groups(self, realm_path: str, missing: set[str]) -> tuple[str, ...]:
        created: list[str] = []
        for name in sorted(missing):
            self._request("POST", f"{realm_path}/groups", json={"name": name})
            created.append(name)
        return tuple(created)

    def _create_scopes(self, realm_path: str, missing: set[str]) -> tuple[str, ...]:
        created: list[str] = []
        for name in sorted(missing):
            self._request(
                "POST",
                f"{realm_path}/client-scopes",
                json={"name": name, "protocol": "openid-connect"},
            )
            created.append(name)
        return tuple(created)


def _apply_client_expectation(payload: dict[str, Any], expected: ClientExpectation) -> None:
    """Apply only documented non-secret client fields."""
    fields = {
        "enabled": expected.enabled,
        "serviceAccountsEnabled": expected.service_accounts_enabled,
        "standardFlowEnabled": expected.standard_flow_enabled,
        "directAccessGrantsEnabled": expected.direct_access_grants_enabled,
    }
    for field, value in fields.items():
        if value is not None:
            payload[field] = value
    if expected.redirect_uris:
        payload["redirectUris"] = sorted(expected.redirect_uris)
    if expected.web_origins:
        payload["webOrigins"] = sorted(expected.web_origins)
    if expected.post_logout_redirect_uri is not None:
        attributes = dict(payload.get("attributes", {}))
        attributes["post.logout.redirect.uris"] = expected.post_logout_redirect_uri
        payload["attributes"] = attributes
