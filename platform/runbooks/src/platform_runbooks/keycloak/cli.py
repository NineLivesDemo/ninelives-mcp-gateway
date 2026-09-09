"""Command-line entry point for read-only Keycloak platform checks."""

from __future__ import annotations

import argparse
import json
import os
from dataclasses import asdict

from .contract import build_mcp_registry_expectation
from .credentials import admin_token_from_key_vault
from .discovery import KeycloakAdminClient
from .plan import build_plan
from .verify import verify_snapshot


def _required_environment(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"Required environment variable {name} is missing")
    return value


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Read-only MCP Registry Keycloak planner")
    parser.add_argument("--url", default=os.environ.get("KEYCLOAK_URL"))
    parser.add_argument("--realm", default=os.environ.get("KEYCLOAK_REALM", "mcp-gateway"))
    parser.add_argument("--vault-url", default=os.environ.get("AZURE_KEY_VAULT_URL"))
    parser.add_argument(
        "--password-secret",
        default=os.environ.get("KEYCLOAK_ADMIN_PASSWORD_SECRET", "keycloak-admin-password"),
    )
    parser.add_argument("--admin-user", default=os.environ.get("KEYCLOAK_ADMIN", "admin"))
    parser.add_argument("--registry-url", required=True)
    parser.add_argument("--auth-server-url", required=True)
    parser.add_argument("--keycloak-external-url", required=True)
    parser.add_argument(
        "--verify", action="store_true", help="fail if OIDC or desired-state checks fail"
    )
    return parser


def main() -> int:
    """Run read-only Keycloak discovery and planning."""
    args = _parser().parse_args()
    base_url = args.url or _required_environment("KEYCLOAK_URL")
    vault_url = args.vault_url or _required_environment("AZURE_KEY_VAULT_URL")
    token = admin_token_from_key_vault(
        base_url,
        args.admin_user,
        vault_url,
        args.password_secret,
    )
    with KeycloakAdminClient(base_url, args.realm, token) as client:
        snapshot = client.discover()
    expectation = build_mcp_registry_expectation(
        args.registry_url,
        args.auth_server_url,
        args.keycloak_external_url,
    )
    plan = build_plan(snapshot, expectation)
    output = {"plan": asdict(plan), "snapshot": asdict(snapshot)}
    verification = None
    if args.verify:
        verification = verify_snapshot(snapshot, expectation)
        output["verification"] = asdict(verification)
    print(json.dumps(output, indent=2, sort_keys=True))
    if verification is not None and not verification.passed:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
