"""Tests for read-only Keycloak verification."""

from platform_runbooks.keycloak.discovery import KeycloakSnapshot
from platform_runbooks.keycloak.plan import KeycloakExpectation
from platform_runbooks.keycloak.verify import verify_snapshot


def test_verify_snapshot_accepts_required_oidc_metadata() -> None:
    snapshot = KeycloakSnapshot(
        realm={"realm": "mcp-gateway"},
        clients=[],
        groups=[],
        client_scopes=[],
        oidc_metadata={
            "issuer": "https://idp.example.test/realms/mcp-gateway",
            "authorization_endpoint": "https://idp.example.test/auth",
            "token_endpoint": "https://idp.example.test/token",
            "registration_endpoint": "https://idp.example.test/register",
            "jwks_uri": "https://idp.example.test/certs",
            "code_challenge_methods_supported": ["S256"],
        },
    )
    expectation = KeycloakExpectation(
        realm="mcp-gateway",
        expected_issuer="https://idp.example.test/realms/mcp-gateway",
        clients=(),
        required_groups=frozenset(),
        required_client_scopes=frozenset(),
    )

    result = verify_snapshot(snapshot, expectation)

    assert result.passed


def test_verify_snapshot_rejects_missing_dcr_metadata() -> None:
    snapshot = KeycloakSnapshot(
        realm={"realm": "mcp-gateway"},
        clients=[],
        groups=[],
        client_scopes=[],
        oidc_metadata={"issuer": "https://idp.example.test/realms/mcp-gateway"},
    )
    expectation = KeycloakExpectation(
        realm="mcp-gateway",
        clients=(),
        required_groups=frozenset(),
        required_client_scopes=frozenset(),
    )

    result = verify_snapshot(snapshot, expectation)

    assert not result.passed
    assert any(check.name == "oidc.dcr" and not check.passed for check in result.checks)
