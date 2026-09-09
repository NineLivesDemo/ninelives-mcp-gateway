"""Concurrency and audit primitives for platform operations."""

from __future__ import annotations

import hashlib
import json
import re
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

from azure.core.exceptions import HttpResponseError, ResourceExistsError, ResourceNotFoundError
from azure.storage.blob import BlobServiceClient, ContainerClient


class LockUnavailable(RuntimeError):
    """Raised when another operation owns the target lock."""


class LockStore(Protocol):
    """Backend contract for a durable distributed lock."""

    def acquire(self, key: str, owner: str, lease_seconds: int) -> None:
        """Acquire a lock or raise LockUnavailable."""

    def renew(self, key: str, owner: str, lease_seconds: int) -> None:
        """Renew a lock owned by the caller."""

    def release(self, key: str, owner: str) -> None:
        """Release a lock owned by the caller."""


class AuditSink(Protocol):
    """Backend contract for durable redacted audit records."""

    def record(self, event: AuditEvent) -> None:
        """Persist one audit event."""


@dataclass(frozen=True)
class AuditEvent:
    """Secret-free audit record for one operation."""

    correlation_id: str
    actor: str
    operation: str
    role: str
    vm_name: str
    artifact_version: str
    result: str
    started_at: str
    duration_seconds: float


_BLOB_KEY = re.compile(r"^[A-Za-z0-9_.:-]+$")


class AzureBlobLockStore:
    """Lease-based lock store backed by one Azure Blob container."""

    def __init__(self, container: ContainerClient) -> None:
        self._container = container
        self._leases: dict[tuple[str, str], object] = {}

    @classmethod
    def from_storage_account(
        cls,
        account_url: str,
        container_name: str,
        credential: object,
    ) -> AzureBlobLockStore:
        """Create a lock store using an injected Azure credential."""
        service = BlobServiceClient(account_url=account_url, credential=credential)
        return cls(service.get_container_client(container_name))

    def acquire(self, key: str, owner: str, lease_seconds: int) -> None:
        """Acquire a renewable Azure blob lease for a validated operation key."""
        if not key or not owner or lease_seconds not in range(15, 61):
            raise ValueError("Lock key, owner, and lease duration are invalid")
        blob = self._container.get_blob_client(self._blob_name(key))
        try:
            blob.upload_blob(b"platform lock", overwrite=False)
        except ResourceExistsError:
            pass
        try:
            lease = blob.acquire_lease(lease_duration=lease_seconds)
        except HttpResponseError as error:
            if error.status_code not in {409, 412}:
                raise
            raise LockUnavailable(f"Lock is already held for {key}") from error
        self._leases[(key, owner)] = lease

    def renew(self, key: str, owner: str, lease_seconds: int) -> None:
        """Renew the Azure lease before a bounded host action."""
        if lease_seconds not in range(15, 61):
            raise ValueError("Lock lease must be between 15 and 60 seconds")
        lease = self._leases.get((key, owner))
        if lease is None:
            raise LockUnavailable(f"Lock is not owned by {owner}")
        try:
            lease.renew(lease_duration=lease_seconds)
        except ResourceNotFoundError as error:
            raise LockUnavailable(f"Lock lease no longer exists for {key}") from error

    def release(self, key: str, owner: str) -> None:
        """Release only the lease acquired by this worker and owner."""
        lease = self._leases.pop((key, owner), None)
        if lease is None:
            raise LockUnavailable(f"Lock is not owned by {owner}")
        try:
            lease.release()
        except ResourceNotFoundError as error:
            raise LockUnavailable(f"Lock lease no longer exists for {key}") from error

    @staticmethod
    def _blob_name(key: str) -> str:
        if not _BLOB_KEY.fullmatch(key):
            raise ValueError("Lock key contains unsupported characters")
        return f"locks/{hashlib.sha256(key.encode()).hexdigest()}.lease"


class AzureBlobAuditSink:
    """Append-only audit sink that writes one immutable JSON blob per event."""

    def __init__(self, container: ContainerClient) -> None:
        self._container = container

    @classmethod
    def from_storage_account(
        cls,
        account_url: str,
        container_name: str,
        credential: object,
    ) -> AzureBlobAuditSink:
        """Create an audit sink using an injected Azure credential."""
        service = BlobServiceClient(account_url=account_url, credential=credential)
        return cls(service.get_container_client(container_name))

    def record(self, event: AuditEvent) -> None:
        """Write a fixed-shape event without allowing overwrite."""
        blob_name = (
            f"events/{event.started_at.replace(':', '').replace('+', '_')}-{uuid.uuid4().hex}.json"
        )
        payload = json.dumps(event.__dict__, sort_keys=True, separators=(",", ":")).encode()
        self._container.upload_blob(name=blob_name, data=payload, overwrite=False)


class InMemoryLockStore:
    """Deterministic lock store used by unit tests and local dry runs."""

    def __init__(self) -> None:
        self._owners: dict[str, str] = {}

    def acquire(self, key: str, owner: str, lease_seconds: int) -> None:
        if lease_seconds <= 0:
            raise ValueError("Lock lease must be positive")
        current_owner = self._owners.get(key)
        if current_owner is not None and current_owner != owner:
            raise LockUnavailable(f"Lock is already held for {key}")
        self._owners[key] = owner

    def renew(self, key: str, owner: str, lease_seconds: int) -> None:
        if lease_seconds <= 0:
            raise ValueError("Lock lease must be positive")
        if self._owners.get(key) != owner:
            raise LockUnavailable(f"Lock is not owned by {owner}")

    def release(self, key: str, owner: str) -> None:
        if self._owners.get(key) != owner:
            raise LockUnavailable(f"Lock is not owned by {owner}")
        del self._owners[key]


class InMemoryAuditSink:
    """Deterministic audit sink for tests; records contain no payload data."""

    def __init__(self) -> None:
        self.events: list[AuditEvent] = []

    def record(self, event: AuditEvent) -> None:
        self.events.append(event)


def new_audit_event(
    *,
    correlation_id: str,
    actor: str,
    operation: str,
    role: str,
    vm_name: str,
    artifact_version: str,
    result: str,
    started_at: datetime,
    duration_seconds: float,
) -> AuditEvent:
    """Create a normalized audit event without accepting arbitrary payloads."""
    if not all((correlation_id, actor, operation, role, vm_name, artifact_version, result)):
        raise ValueError("Audit identity and result fields are required")
    if started_at.tzinfo is None:
        raise ValueError("Audit timestamps must include a timezone")
    if duration_seconds < 0:
        raise ValueError("Audit duration cannot be negative")
    return AuditEvent(
        correlation_id=correlation_id,
        actor=actor,
        operation=operation,
        role=role,
        vm_name=vm_name,
        artifact_version=artifact_version,
        result=result,
        started_at=started_at.astimezone(UTC).isoformat(),
        duration_seconds=duration_seconds,
    )
