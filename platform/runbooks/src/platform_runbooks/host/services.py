"""Deterministic planning for host service state."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class DesiredService:
    """Required state for one systemd-managed service."""

    name: str
    enabled: bool = True
    active: bool = True
    restart_on_file_change: bool = True


@dataclass(frozen=True)
class ObservedService:
    """Redacted systemd state."""

    enabled: bool
    active: bool


@dataclass(frozen=True)
class ServiceChange:
    """One service action required by reconciliation."""

    service: str
    action: str


def plan_services(
    desired: tuple[DesiredService, ...],
    observed: dict[str, ObservedService],
    changed_files: frozenset[str] = frozenset(),
) -> tuple[ServiceChange, ...]:
    """Plan enable/start/restart actions without invoking systemd."""
    changes: list[ServiceChange] = []
    for service in desired:
        current = observed.get(service.name)
        if current is None:
            changes.append(ServiceChange(service.name, "inspect"))
            continue
        if current.enabled != service.enabled:
            changes.append(ServiceChange(service.name, "enable" if service.enabled else "disable"))
        if current.active != service.active:
            changes.append(ServiceChange(service.name, "start" if service.active else "stop"))
        if service.restart_on_file_change and changed_files:
            changes.append(ServiceChange(service.name, "restart"))
    return tuple(changes)
