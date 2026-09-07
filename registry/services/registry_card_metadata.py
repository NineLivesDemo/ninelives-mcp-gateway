"""Shared Registry Card metadata derived from deployment configuration."""

import os
from typing import Any
from urllib.parse import urlparse

from ..constants import REGISTRY_CONSTANTS
from ..core.config import settings
from ..schemas.registry_card import RegistryAuthConfig


def build_registry_card_system_fields() -> dict[str, Any]:
    """Build the Registry Card fields controlled by deployment configuration."""
    _validate_external_url(settings.registry_url, "REGISTRY_URL")
    if settings.auth_provider == "keycloak":
        _validate_external_url(
            os.getenv("KEYCLOAK_EXTERNAL_URL", "http://localhost:8080"),
            "KEYCLOAK_EXTERNAL_URL",
        )

    return {
        "registry_url": settings.registry_url,
        "organization_name": settings.registry_organization_name,
        "federation_api_version": REGISTRY_CONSTANTS.FEDERATION_API_VERSION,
        "federation_endpoint": f"{settings.registry_url}/api/v1/federation",
        "authentication": _build_authentication_config(),
    }


def _validate_external_url(url: str, setting_name: str) -> None:
    """Reject malformed or non-HTTPS non-loopback URLs in secure deployments."""
    parsed = urlparse(url)
    hostname = (parsed.hostname or "").lower()
    loopback_hosts = {"localhost", "127.0.0.1", "::1"}

    if not parsed.scheme or not parsed.netloc or not hostname:
        raise ValueError(f"{setting_name} must be an absolute URL")

    if settings.mcp_https_required and parsed.scheme != "https" and hostname not in loopback_hosts:
        raise ValueError(
            f"{setting_name} must use HTTPS outside local loopback development: {url}"
        )


def _build_authentication_config() -> RegistryAuthConfig:
    """Build provider-specific OAuth metadata for the Registry Card."""
    oauth2_issuer: str | None = None
    oauth2_token_endpoint: str | None = None

    if settings.auth_provider == "okta":
        okta_domain = os.getenv("OKTA_DOMAIN")
        okta_auth_server_id = os.getenv("OKTA_AUTH_SERVER_ID", "default")
        if okta_domain:
            oauth2_issuer = f"https://{okta_domain}/oauth2/{okta_auth_server_id}"
            oauth2_token_endpoint = (
                f"https://{okta_domain}/oauth2/{okta_auth_server_id}/v1/token"
            )
    elif settings.auth_provider == "keycloak":
        keycloak_external_url = os.getenv("KEYCLOAK_EXTERNAL_URL", "http://localhost:8080").rstrip(
            "/"
        )
        keycloak_realm = os.getenv("KEYCLOAK_REALM", "mcp-gateway")
        oauth2_issuer = f"{keycloak_external_url}/realms/{keycloak_realm}"
        oauth2_token_endpoint = (
            f"{keycloak_external_url}/realms/{keycloak_realm}/protocol/openid-connect/token"
        )
    elif settings.auth_provider == "entra":
        entra_tenant_id = os.getenv("ENTRA_TENANT_ID")
        if entra_tenant_id:
            oauth2_issuer = f"https://login.microsoftonline.com/{entra_tenant_id}/v2.0"
            oauth2_token_endpoint = (
                f"https://login.microsoftonline.com/{entra_tenant_id}/oauth2/v2.0/token"
            )
    elif settings.auth_provider == "cognito":
        cognito_user_pool_id = os.getenv("COGNITO_USER_POOL_ID")
        cognito_domain = os.getenv("COGNITO_DOMAIN")
        aws_region = os.getenv("AWS_REGION", "us-east-1")
        if cognito_user_pool_id:
            oauth2_issuer = f"https://cognito-idp.{aws_region}.amazonaws.com/{cognito_user_pool_id}"
        if cognito_domain:
            oauth2_token_endpoint = (
                f"https://{cognito_domain}.auth.{aws_region}.amazoncognito.com/oauth2/token"
            )

    return RegistryAuthConfig(
        oauth2_issuer=oauth2_issuer,
        oauth2_token_endpoint=oauth2_token_endpoint,
    )
