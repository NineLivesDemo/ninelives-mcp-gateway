"""Azure Automation entry point for safe platform runbook operations."""

from __future__ import annotations

import json
import os
from dataclasses import asdict

from platform_runbooks.automation import RunbookRequest, build_job
from platform_runbooks.host.discovery import SubprocessRunner, discover_role
from platform_runbooks.host.plan import plan_host
from platform_runbooks.host.services import DesiredService
from platform_runbooks.manifest import get_role_manifest
from platform_runbooks.registry_schema import verify_scope_collection, verify_scope_documents


def _required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"Required runbook input {name} is missing")
    return value


def _request_from_environment() -> RunbookRequest:
    operation = _required("PLATFORM_OPERATION")
    role = _required("PLATFORM_ROLE")
    artifact_version = _required("PLATFORM_ARTIFACT_VERSION")
    return RunbookRequest(
        operation=operation,
        role=role,
        artifact_version=artifact_version,
        approved_plan_id=os.environ.get("PLATFORM_APPROVED_PLAN_ID"),
        confirmation=os.environ.get("PLATFORM_CONFIRMATION"),
        existing_realm_verified=os.environ.get("PLATFORM_EXISTING_REALM_VERIFIED") == "true",
    )


def _discover(role: str) -> dict[str, object]:
    manifest = get_role_manifest(role)
    snapshot = discover_role(
        manifest,
        SubprocessRunner(),
        probe=os.environ.get("PLATFORM_SKIP_HEALTH") != "true",
    )
    return {"snapshot": asdict(snapshot)}


def _plan(role: str) -> dict[str, object]:
    manifest = get_role_manifest(role)
    snapshot = discover_role(
        manifest,
        SubprocessRunner(),
        probe=os.environ.get("PLATFORM_SKIP_HEALTH") != "true",
    )
    host_plan = plan_host(
        manifest.role,
        manifest.vm_name,
        (),
        snapshot.files,
        (DesiredService(manifest.systemd_unit),),
        snapshot.services,
    )
    return {"snapshot": asdict(snapshot), "plan": asdict(host_plan)}


def _verify(role: str) -> tuple[dict[str, object], bool]:
    manifest = get_role_manifest(role)
    snapshot = discover_role(manifest, SubprocessRunner())
    services_ok = all(state.active for state in snapshot.services.values())
    health_ok = all(result.passed for result in snapshot.health)
    return {
        "snapshot": asdict(snapshot),
        "checks": {"services_active": services_ok, "health": health_ok},
    }, services_ok and health_ok


def _registry_schema_verify() -> tuple[dict[str, object], bool]:
    """Validate supplied Registry scope documents without contacting MongoDB."""
    raw_documents = os.environ.get("PLATFORM_REGISTRY_SCOPE_DOCUMENTS")
    if raw_documents:
        try:
            documents = json.loads(raw_documents)
        except json.JSONDecodeError as error:
            raise ValueError("PLATFORM_REGISTRY_SCOPE_DOCUMENTS must contain valid JSON") from error
        result = verify_scope_documents(documents)
    else:
        secret_path = "/etc/platform/secrets/raw/mongodb-connection-string"
        try:
            with open(secret_path, encoding="utf-8") as secret_file:
                connection_string = secret_file.read().rstrip("\r\n")
        except OSError as error:
            raise RuntimeError("Registry schema check requires MongoDB secret file or JSON documents") from error
        result = verify_scope_collection(
            connection_string,
            os.environ.get("DOCUMENTDB_DATABASE", "mcp_registry"),
            os.environ.get("DOCUMENTDB_NAMESPACE", "default"),
        )
    return {"registry_schema": result}, result["valid"] is True


def _execute_read_only(operation: str, role: str) -> tuple[dict[str, object], bool]:
    if operation == "discover":
        return _discover(role), True
    if operation == "plan":
        return _plan(role), True
    if operation == "verify":
        return _verify(role)
    if operation == "registry-schema-verify":
        return _registry_schema_verify()
    raise RuntimeError(
        f"Operation {operation} is validated but execution is disabled until durable lock and audit backends are configured"
    )


def main() -> int:
    """Validate and execute one safe read-only Automation job."""
    request = _request_from_environment()
    job = build_job(
        request,
        worker_group=os.environ.get("PLATFORM_WORKER_GROUP", "platform-private-workers"),
        timeout_seconds=int(os.environ.get("PLATFORM_TIMEOUT_SECONDS", "900")),
    )
    result, passed = _execute_read_only(request.operation, request.role)
    output = {"job": asdict(job), "manifest": asdict(get_role_manifest(request.role)), **result}
    output["status"] = "verified" if request.operation in {"verify", "registry-schema-verify"} and passed else "completed"
    print(json.dumps(output, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
