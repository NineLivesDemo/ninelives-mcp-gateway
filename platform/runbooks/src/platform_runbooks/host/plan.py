"""Pure host reconciliation planning."""

from __future__ import annotations

from dataclasses import dataclass

from .files import DesiredFile, ObservedFile, content_sha256, validate_managed_path
from .services import DesiredService, ObservedService, ServiceChange, plan_services


@dataclass(frozen=True)
class FileChange:
    """One managed-file difference without including its content."""

    path: str
    action: str
    expected_sha256: str
    actual_sha256: str | None
    expected_mode: int
    actual_mode: int | None


@dataclass(frozen=True)
class HostPlan:
    """Deterministic host plan safe to serialize into an approval artifact."""

    role: str
    vm_name: str
    file_changes: tuple[FileChange, ...]
    service_changes: tuple[ServiceChange, ...]

    @property
    def is_noop(self) -> bool:
        """Return whether no host changes are required."""
        return not self.file_changes and not self.service_changes


def plan_host(
    role: str,
    vm_name: str,
    desired_files: tuple[DesiredFile, ...],
    observed_files: dict[str, ObservedFile],
    desired_services: tuple[DesiredService, ...],
    observed_services: dict[str, ObservedService],
) -> HostPlan:
    """Compare desired host state without reading or exposing secret contents."""
    if not role or not vm_name:
        raise ValueError("Host role and VM name are required")
    file_changes: list[FileChange] = []
    changed_paths: set[str] = set()
    for desired in desired_files:
        path = validate_managed_path(desired.path)
        expected_hash = content_sha256(desired.content)
        observed = observed_files.get(path, ObservedFile(False, None, None))
        if not observed.exists or observed.sha256 != expected_hash or observed.mode != desired.mode:
            file_changes.append(
                FileChange(
                    path,
                    "create" if not observed.exists else "replace",
                    expected_hash,
                    observed.sha256,
                    desired.mode,
                    observed.mode,
                )
            )
            changed_paths.add(path)
    service_changes = plan_services(
        desired_services,
        observed_services,
        frozenset(changed_paths),
    )
    return HostPlan(role, vm_name, tuple(file_changes), service_changes)
