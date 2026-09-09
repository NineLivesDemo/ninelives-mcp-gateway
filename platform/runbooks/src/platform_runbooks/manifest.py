"""Versioned non-secret manifests for platform VM roles."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class HealthProbe:
    """One local HTTP health probe expected for a role."""

    name: str
    url: str
    expected_status: int = 200


@dataclass(frozen=True)
class RoleManifest:
    """Non-secret desired host contract for one platform role."""

    role: str
    vm_name: str
    compose_path: str
    systemd_unit: str
    managed_paths: tuple[str, ...]
    secret_paths: tuple[str, ...]
    health_probes: tuple[HealthProbe, ...]
    dependencies: tuple[str, ...] = ()


_MANIFESTS = {
    "keycloak": RoleManifest(
        role="keycloak",
        vm_name="vm-platform-keycloak",
        compose_path="/opt/platform/compose/keycloak/compose.yaml",
        systemd_unit="platform-keycloak.service",
        managed_paths=(
            "/opt/platform/compose/keycloak/compose.yaml",
            "/etc/platform/secrets/keycloak.env",
        ),
        secret_paths=(
            "/etc/platform/secrets/raw/keycloak-admin-password",
            "/etc/platform/secrets/raw/keycloak-db-password",
        ),
        health_probes=(HealthProbe("keycloak-readiness", "http://10.60.5.4:8080/health/ready"),),
    ),
    "apps": RoleManifest(
        role="apps",
        vm_name="vm-platform-apps",
        compose_path="/opt/platform/compose/apps/compose.yaml",
        systemd_unit="platform-apps.service",
        managed_paths=(
            "/opt/platform/compose/apps/compose.yaml",
            "/etc/platform/secrets/registry.env",
            "/etc/platform/secrets/auth-server.env",
        ),
        secret_paths=(
            "/etc/platform/secrets/raw/registry-secret-key",
            "/etc/platform/secrets/raw/auth-server-nginx-marker-secret",
            "/etc/platform/secrets/raw/mongodb-connection-string",
            "/etc/platform/secrets/raw/embeddings-api-key",
            "/etc/platform/secrets/raw/keycloak-client-secret",
            "/etc/platform/secrets/raw/keycloak-m2m-client-secret",
            "/etc/platform/secrets/raw/openbao-registry-token",
            "/etc/platform/secrets/raw/platform-ca-cert",
        ),
        health_probes=(
            HealthProbe("registry", "http://10.60.4.4:8080/health"),
            HealthProbe("auth-server", "http://127.0.0.1:8888/health"),
            HealthProbe("mcp-gateway", "http://127.0.0.1:8003/health"),
        ),
        dependencies=("keycloak", "openbao"),
    ),
    "edge": RoleManifest(
        role="edge",
        vm_name="vm-platform-edge",
        compose_path="/opt/platform/compose/edge/compose.yaml",
        systemd_unit="platform-edge.service",
        managed_paths=(
            "/opt/platform/compose/edge/compose.yaml",
            "/opt/platform/config/edge/apisix.yaml",
            "/opt/platform/compose/edge/registry-route.json",
            "/opt/platform/compose/edge/keycloak-route.json",
            "/etc/platform/secrets/edge.env",
        ),
        secret_paths=("/etc/platform/secrets/cloudflare-tunnel-token",),
        health_probes=(HealthProbe("apisix", "http://127.0.0.1:9080/health"),),
        dependencies=("etcd", "apps", "keycloak"),
    ),
    "etcd": RoleManifest(
        role="etcd",
        vm_name="vm-platform-etcd",
        compose_path="/opt/platform/compose/etcd/compose.yaml",
        systemd_unit="platform-etcd.service",
        managed_paths=("/opt/platform/compose/etcd/compose.yaml",),
        secret_paths=(
            "/etc/platform/tls/platform-ca.crt",
            "/etc/platform/tls/etcd-server.crt",
            "/etc/platform/tls/etcd-server.key",
            "/etc/platform/tls/etcd-client.crt",
            "/etc/platform/tls/etcd-client.key",
        ),
        health_probes=(HealthProbe("etcd", "https://10.60.2.4:2379/health"),),
    ),
    "openbao": RoleManifest(
        role="openbao",
        vm_name="vm-platform-openbao",
        compose_path="/opt/platform/compose/openbao/compose.yaml",
        systemd_unit="platform-openbao.service",
        managed_paths=(
            "/opt/platform/compose/openbao/compose.yaml",
            "/opt/platform/config/openbao/openbao.hcl",
            "/etc/platform/config/openbao.env",
        ),
        secret_paths=(
            "/etc/platform/tls/platform-ca.crt",
            "/etc/platform/tls/openbao.crt",
            "/etc/platform/tls/openbao.key",
        ),
        health_probes=(HealthProbe("openbao", "https://10.60.3.4:8200/v1/sys/health"),),
        dependencies=("etcd",),
    ),
}


def get_role_manifest(role: str) -> RoleManifest:
    """Return a copy-safe manifest for one allowlisted role."""
    try:
        return _MANIFESTS[role]
    except KeyError as error:
        raise ValueError(f"Unknown platform role: {role}") from error
