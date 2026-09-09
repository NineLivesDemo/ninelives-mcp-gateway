"""Approval-gated host mutation executor."""

from __future__ import annotations

import hashlib
import json
import time
from collections.abc import Callable
from datetime import UTC, datetime

from platform_runbooks.operations import AuditSink, LockStore, new_audit_event

from .discovery import CommandRunner
from .files import DesiredFile, write_atomic
from .plan import HostPlan

_ALLOWED_ACTIONS = frozenset({"enable", "disable", "start", "stop", "restart"})


def plan_id(plan: HostPlan) -> str:
    """Return the immutable approval identifier for a host plan."""
    encoded = json.dumps(
        {
            "role": plan.role,
            "vm_name": plan.vm_name,
            "file_changes": [change.__dict__ for change in plan.file_changes],
            "service_changes": [change.__dict__ for change in plan.service_changes],
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
    return hashlib.sha256(encoded).hexdigest()


def apply_host_plan(
    plan: HostPlan,
    desired_files: tuple[DesiredFile, ...],
    runner: CommandRunner,
    lock_store: LockStore,
    audit_sink: AuditSink,
    *,
    owner: str,
    approved_plan_id: str,
    confirmation: str,
    actor: str,
    correlation_id: str,
    artifact_version: str,
    writer: Callable[[DesiredFile], None] = write_atomic,
) -> None:
    """Apply one approved host plan and renew its bounded distributed lease."""
    if confirmation != "APPLY":
        raise ValueError("Host mutation requires the exact confirmation phrase APPLY")
    expected_plan_id = plan_id(plan)
    if approved_plan_id != expected_plan_id:
        raise ValueError("Approved plan ID does not match the current plan")
    if not owner:
        raise ValueError("Lock owner is required")
    started = datetime.now(UTC)
    started_monotonic = time.monotonic()
    result = "failed"
    lock_key = f"platform:{plan.role}:{plan.vm_name}"
    lock_store.acquire(lock_key, owner, 60)
    renew = getattr(lock_store, "renew", None)
    try:
        desired_by_path = {desired.path: desired for desired in desired_files}
        for change in plan.file_changes:
            if callable(renew):
                renew(lock_key, owner, 60)
            desired = desired_by_path.get(change.path)
            if desired is None:
                raise ValueError(f"Approved plan has no content for {change.path}")
            writer(desired)
        for change in plan.service_changes:
            if change.action == "inspect":
                continue
            if change.action not in _ALLOWED_ACTIONS:
                raise ValueError(f"Unsupported service action: {change.action}")
            if callable(renew):
                renew(lock_key, owner, 60)
            result = runner.run(("systemctl", change.action, change.service), timeout=45)
            if result.returncode != 0:
                raise RuntimeError(f"systemctl {change.action} failed for {change.service}")
        result = "success"
    finally:
        lock_store.release(lock_key, owner)
        audit_sink.record(
            new_audit_event(
                correlation_id=correlation_id,
                actor=actor,
                operation="apply",
                role=plan.role,
                vm_name=plan.vm_name,
                artifact_version=artifact_version,
                result=result,
                started_at=started,
                duration_seconds=time.monotonic() - started_monotonic,
            )
        )
