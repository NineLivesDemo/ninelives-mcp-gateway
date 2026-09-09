"""Tests for the approval-gated host executor."""

from platform_runbooks.host.discovery import CommandResult
from platform_runbooks.host.executor import apply_host_plan, plan_id
from platform_runbooks.host.files import DesiredFile
from platform_runbooks.host.plan import HostPlan
from platform_runbooks.host.services import ServiceChange
from platform_runbooks.operations import InMemoryAuditSink, InMemoryLockStore


def test_apply_requires_matching_plan_and_records_audit() -> None:
    plan = HostPlan(
        "apps",
        "vm-platform-apps",
        (),
        (ServiceChange("platform-apps.service", "restart"),),
    )
    calls: list[tuple[str, ...]] = []

    class Runner:
        def run(self, args: tuple[str, ...], timeout: float) -> CommandResult:
            calls.append(args)
            return CommandResult(0, "", "")

    audit = InMemoryAuditSink()
    apply_host_plan(
        plan,
        (),
        Runner(),
        InMemoryLockStore(),
        audit,
        owner="job-1",
        approved_plan_id=plan_id(plan),
        confirmation="APPLY",
        actor="operator@example.test",
        correlation_id="corr-1",
        artifact_version="git-abc123",
    )

    assert calls == [("systemctl", "restart", "platform-apps.service")]
    assert audit.events[0].result == "success"


def test_apply_writes_only_approved_desired_files() -> None:
    desired = DesiredFile("/etc/platform/secrets/registry.env", b"fixture")
    plan = HostPlan(
        "apps",
        "vm-platform-apps",
        (),
        (),
    )
    writes: list[str] = []

    apply_host_plan(
        plan,
        (desired,),
        type("Runner", (), {"run": lambda self, args, timeout: CommandResult(0, "", "")})(),
        InMemoryLockStore(),
        InMemoryAuditSink(),
        owner="job-1",
        approved_plan_id=plan_id(plan),
        confirmation="APPLY",
        actor="operator@example.test",
        correlation_id="corr-2",
        artifact_version="git-abc123",
        writer=lambda item: writes.append(item.path),
    )

    assert writes == []
