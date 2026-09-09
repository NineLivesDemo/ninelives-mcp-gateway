"""Tests for host-local planning and protected files."""

import pytest
from platform_runbooks.host.files import (
    DesiredFile,
    ObservedFile,
    content_sha256,
    validate_managed_path,
)
from platform_runbooks.host.plan import plan_host
from platform_runbooks.host.services import DesiredService, ObservedService


def test_host_plan_is_noop_for_matching_state() -> None:
    desired = DesiredFile("/etc/mcp-gateway/app.env", b"PORT=8080\n")
    plan = plan_host(
        "apps",
        "vm-platform-apps",
        (desired,),
        {desired.path: ObservedFile(True, content_sha256(desired.content), desired.mode)},
        (DesiredService("platform-apps.service"),),
        {"platform-apps.service": ObservedService(True, True)},
    )

    assert plan.is_noop


def test_host_plan_restarts_affected_service_without_exposing_content() -> None:
    desired = DesiredFile("/etc/mcp-gateway/app.env", b"SECRET=value\n")
    plan = plan_host(
        "apps",
        "vm-platform-apps",
        (desired,),
        {},
        (DesiredService("platform-apps.service"),),
        {"platform-apps.service": ObservedService(True, True)},
    )

    assert plan.file_changes[0].expected_sha256 == content_sha256(desired.content)
    assert "SECRET=value" not in repr(plan)
    assert plan.service_changes[0].action == "restart"


@pytest.mark.parametrize("path", ["relative.env", "/etc/shadow", "/opt/mcp-gateway/../etc/passwd"])
def test_managed_path_allowlist_fails_closed(path: str) -> None:
    with pytest.raises(ValueError):
        validate_managed_path(path)
