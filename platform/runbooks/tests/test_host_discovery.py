"""Tests for read-only host discovery."""

from platform_runbooks.host.discovery import CommandResult, discover_role
from platform_runbooks.manifest import get_role_manifest


class FakeRunner:
    def __init__(self) -> None:
        self.calls: list[tuple[str, ...]] = []

    def run(self, args: tuple[str, ...], timeout: float) -> CommandResult:
        self.calls.append(args)
        return CommandResult(0, "enabled\n", "")


def test_discover_role_uses_fixed_systemd_arguments_without_health_probe() -> None:
    runner = FakeRunner()
    manifest = get_role_manifest("keycloak")

    snapshot = discover_role(manifest, runner, probe=False)

    assert snapshot.role == "keycloak"
    assert snapshot.services["platform-keycloak.service"].active
    assert runner.calls == [
        ("systemctl", "is-enabled", "platform-keycloak.service"),
        ("systemctl", "is-active", "platform-keycloak.service"),
    ]
    assert snapshot.health == ()


def test_discover_role_never_returns_managed_file_contents() -> None:
    runner = FakeRunner()
    snapshot = discover_role(get_role_manifest("apps"), runner, probe=False)

    assert all(not hasattr(state, "content") for state in snapshot.files.values())
