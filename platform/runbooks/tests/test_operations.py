"""Tests for operation locks and audit records."""

from datetime import UTC, datetime

import pytest
from platform_runbooks.operations import (
    AuditEvent,
    InMemoryAuditSink,
    InMemoryLockStore,
    LockUnavailable,
    new_audit_event,
)


def test_lock_store_fails_closed_for_competing_owner() -> None:
    locks = InMemoryLockStore()
    locks.acquire("apps", "job-1", 60)

    with pytest.raises(LockUnavailable):
        locks.acquire("apps", "job-2", 60)
    with pytest.raises(LockUnavailable):
        locks.release("apps", "job-2")

    locks.release("apps", "job-1")
    locks.acquire("apps", "job-2", 60)


def test_audit_event_is_fixed_shape_and_secret_free() -> None:
    sink = InMemoryAuditSink()
    event = new_audit_event(
        correlation_id="corr-1",
        actor="operator@example.test",
        operation="verify",
        role="apps",
        vm_name="vm-platform-apps",
        artifact_version="git-abc123",
        result="success",
        started_at=datetime(2026, 9, 9, tzinfo=UTC),
        duration_seconds=1.25,
    )
    sink.record(event)

    assert isinstance(sink.events[0], AuditEvent)
    assert sink.events[0].started_at.endswith("+00:00")
    assert "password" not in repr(sink.events[0]).lower()


class _FakeLease:
    def __init__(self) -> None:
        self.released = False

    def release(self) -> None:
        self.released = True


class _FakeBlob:
    def __init__(self) -> None:
        self.created = False
        self.lease = _FakeLease()

    def upload_blob(self, data: bytes, overwrite: bool) -> None:
        assert data == b"platform lock"
        assert not overwrite
        self.created = True

    def acquire_lease(self, lease_duration: int) -> _FakeLease:
        assert lease_duration == 30
        return self.lease


class _FakeContainer:
    def __init__(self) -> None:
        self.blob = _FakeBlob()
        self.events: list[tuple[str, bytes]] = []

    def get_blob_client(self, name: str) -> _FakeBlob:
        assert name.startswith("locks/")
        return self.blob

    def upload_blob(self, name: str, data: bytes, overwrite: bool) -> None:
        assert name.startswith("events/")
        assert not overwrite
        self.events.append((name, data))


def test_azure_blob_lock_store_uses_and_releases_lease() -> None:
    from platform_runbooks.operations import AzureBlobLockStore

    container = _FakeContainer()
    locks = AzureBlobLockStore(container)
    locks.acquire("platform:apps:vm-platform-apps", "job-1", 30)
    locks.release("platform:apps:vm-platform-apps", "job-1")

    assert container.blob.created
    assert container.blob.lease.released


def test_azure_blob_audit_sink_writes_one_fixed_shape_event() -> None:
    from platform_runbooks.operations import AzureBlobAuditSink

    container = _FakeContainer()
    event = new_audit_event(
        correlation_id="corr-blob",
        actor="operator@example.test",
        operation="apply",
        role="apps",
        vm_name="vm-platform-apps",
        artifact_version="git-abc123",
        result="success",
        started_at=datetime(2026, 9, 9, tzinfo=UTC),
        duration_seconds=2.0,
    )
    AzureBlobAuditSink(container).record(event)

    assert len(container.events) == 1
    assert b"operator@example.test" in container.events[0][1]
    assert b"password" not in container.events[0][1].lower()
