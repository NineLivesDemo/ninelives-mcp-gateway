"""Tests for Registry Card metadata derived from deployment configuration."""

from unittest.mock import patch

import pytest

from registry.core.config import settings
from registry.services.registry_card_metadata import build_registry_card_system_fields


@pytest.mark.unit
def test_builds_stable_federation_version_and_external_keycloak_urls(monkeypatch):
    """Registry Card metadata uses protocol and external identity versions."""
    monkeypatch.setenv("KEYCLOAK_EXTERNAL_URL", "http://localhost:8080")

    with (
        patch.object(settings, "auth_provider", "keycloak"),
        patch.object(settings, "registry_url", "http://127.0.0.1:19080"),
        patch.object(settings, "registry_organization_name", "ACME Inc."),
        patch.object(settings, "mcp_https_required", False),
    ):
        fields = build_registry_card_system_fields()

    assert fields["federation_api_version"] == "1.0"
    assert fields["federation_endpoint"] == "http://127.0.0.1:19080/api/v1/federation"
    assert fields["authentication"].oauth2_issuer == (
        "http://localhost:8080/realms/mcp-gateway"
    )
    assert fields["authentication"].oauth2_token_endpoint == (
        "http://localhost:8080/realms/mcp-gateway/protocol/openid-connect/token"
    )


@pytest.mark.unit
def test_rejects_non_https_external_urls_in_secure_deployments():
    """Production-style configuration cannot advertise plaintext remote URLs."""
    with (
        patch.object(settings, "registry_url", "http://registry.example.com"),
        patch.object(settings, "mcp_https_required", True),
    ):
        with pytest.raises(ValueError, match="REGISTRY_URL must use HTTPS"):
            build_registry_card_system_fields()
