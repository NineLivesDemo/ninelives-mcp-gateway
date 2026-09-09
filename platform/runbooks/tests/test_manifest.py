"""Tests for non-secret platform role manifests."""

import pytest
from platform_runbooks.manifest import get_role_manifest


def test_keycloak_manifest_contains_only_managed_non_secret_paths() -> None:
    manifest = get_role_manifest("keycloak")

    assert manifest.vm_name == "vm-platform-keycloak"
    assert manifest.systemd_unit == "platform-keycloak.service"
    assert "/etc/platform/secrets/keycloak.env" in manifest.managed_paths
    assert all("password" in path or "secret" in path for path in manifest.secret_paths)


def test_apps_manifest_declares_health_dependencies() -> None:
    manifest = get_role_manifest("apps")

    assert {probe.name for probe in manifest.health_probes} == {
        "registry",
        "auth-server",
        "mcp-gateway",
    }
    assert manifest.dependencies == ("keycloak", "openbao")


def test_unknown_role_fails_closed() -> None:
    with pytest.raises(ValueError, match="Unknown platform role"):
        get_role_manifest("all")
