"""Read-only discovery of managed host state."""

from __future__ import annotations

import re
import subprocess
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Protocol

import httpx

from platform_runbooks.manifest import HealthProbe, RoleManifest

from .files import ObservedFile, observe_file
from .services import ObservedService

_SERVICE_NAME = re.compile(r"^[A-Za-z0-9_.@-]+\.service$")


@dataclass(frozen=True)
class CommandResult:
    """Redacted result of one host command."""

    returncode: int
    stdout: str
    stderr: str


class CommandRunner(Protocol):
    """Minimal command boundary for host discovery and deterministic tests."""

    def run(self, args: Sequence[str], timeout: float) -> CommandResult:
        """Run one fixed executable with arguments."""


class SubprocessRunner:
    """Linux command runner using argument lists and bounded timeouts."""

    def run(self, args: Sequence[str], timeout: float) -> CommandResult:
        """Run a host command without invoking a shell."""
        result = subprocess.run(
            list(args),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return CommandResult(result.returncode, result.stdout, result.stderr)


@dataclass(frozen=True)
class HealthResult:
    """Redacted result of one HTTP health probe."""

    name: str
    url: str
    passed: bool
    status_code: int | None
    error: str | None = None


@dataclass(frozen=True)
class HostSnapshot:
    """Read-only state required by the host planner."""

    role: str
    vm_name: str
    files: dict[str, ObservedFile]
    services: dict[str, ObservedService]
    health: tuple[HealthResult, ...]


def _service_state(runner: CommandRunner, service_name: str, timeout: float) -> ObservedService:
    if not _SERVICE_NAME.fullmatch(service_name):
        raise ValueError(f"Unsafe systemd service name: {service_name}")
    enabled = runner.run(("systemctl", "is-enabled", service_name), timeout)
    active = runner.run(("systemctl", "is-active", service_name), timeout)
    if enabled.returncode not in {0, 1}:
        raise RuntimeError(f"systemctl is-enabled failed for {service_name}")
    if active.returncode not in {0, 3}:
        raise RuntimeError(f"systemctl is-active failed for {service_name}")
    return ObservedService(enabled.returncode == 0, active.returncode == 0)


def probe_health(probe: HealthProbe, *, timeout: float = 5.0) -> HealthResult:
    """Probe a manifest-owned health URL without returning response content."""
    try:
        with httpx.Client(timeout=timeout, follow_redirects=False) as client:
            response = client.get(probe.url)
    except httpx.HTTPError as error:
        return HealthResult(probe.name, probe.url, False, None, type(error).__name__)
    passed = response.status_code == probe.expected_status
    return HealthResult(
        probe.name,
        probe.url,
        passed,
        response.status_code,
        None if passed else f"expected HTTP {probe.expected_status}",
    )


def discover_role(
    manifest: RoleManifest,
    runner: CommandRunner,
    *,
    timeout: float = 10.0,
    probe: bool = True,
) -> HostSnapshot:
    """Discover one role's files, systemd state, and optional health state."""
    files = {path: observe_file(path) for path in manifest.managed_paths}
    services = {manifest.systemd_unit: _service_state(runner, manifest.systemd_unit, timeout)}
    health = (
        tuple(probe_health(item, timeout=timeout) for item in manifest.health_probes)
        if probe
        else ()
    )
    return HostSnapshot(manifest.role, manifest.vm_name, files, services, health)
