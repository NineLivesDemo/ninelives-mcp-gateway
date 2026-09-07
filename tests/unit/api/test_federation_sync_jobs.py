"""Tests for asynchronous federation sync job lifecycle handling."""

from unittest.mock import AsyncMock, MagicMock

import pytest

import registry.api.federation_routes as federation_routes


@pytest.fixture(autouse=True)
def _clear_sync_jobs():
    """Keep the module-level job registry isolated between tests."""
    federation_routes._federation_sync_jobs.clear()
    federation_routes._federation_sync_tasks.clear()
    yield
    federation_routes._federation_sync_jobs.clear()
    federation_routes._federation_sync_tasks.clear()


@pytest.mark.asyncio
async def test_sync_job_stores_successful_result(monkeypatch):
    """A completed sync is exposed as succeeded with its result."""
    job_id = "job-success"
    federation_routes._federation_sync_jobs[job_id] = {
        "job_id": job_id,
        "status": "queued",
        "config_id": "default",
        "source": "anthropic",
        "submitted_by": "admin",
    }
    result = {"total_synced": 2, "results": {"anthropic": {"count": 2}}}
    perform_sync = AsyncMock(return_value=result)
    monkeypatch.setattr(federation_routes, "_perform_federation_sync", perform_sync)

    await federation_routes._run_federation_sync_job(
        job_id=job_id,
        config_id="default",
        source="anthropic",
        submitted_by="admin",
        repo=AsyncMock(),
    )

    job = federation_routes._federation_sync_jobs[job_id]
    assert job["status"] == "succeeded"
    assert job["result"] == result
    perform_sync.assert_awaited_once()


@pytest.mark.asyncio
async def test_sync_job_stores_failure_without_leaking_exception(monkeypatch):
    """A failed sync is represented in status polling instead of crashing the task."""
    job_id = "job-failure"
    federation_routes._federation_sync_jobs[job_id] = {
        "job_id": job_id,
        "status": "queued",
        "config_id": "default",
        "source": None,
        "submitted_by": "admin",
    }
    monkeypatch.setattr(
        federation_routes,
        "_perform_federation_sync",
        AsyncMock(side_effect=RuntimeError("upstream failure")),
    )

    await federation_routes._run_federation_sync_job(
        job_id=job_id,
        config_id="default",
        source=None,
        submitted_by="admin",
        repo=AsyncMock(),
    )

    job = federation_routes._federation_sync_jobs[job_id]
    assert job["status"] == "failed"
    assert job["error"] == "Federation sync failed"


@pytest.mark.asyncio
async def test_sync_route_returns_accepted_job(monkeypatch):
    """The HTTP endpoint queues work instead of waiting for the import."""
    repo = MagicMock()
    repo.get_config = AsyncMock(return_value=object())
    monkeypatch.setattr(federation_routes, "_validate_federation_endpoints", lambda _: None)
    monkeypatch.setattr(federation_routes, "set_audit_action", lambda *args, **kwargs: None)
    perform_sync = AsyncMock(return_value={"total_synced": 1})
    monkeypatch.setattr(federation_routes, "_perform_federation_sync", perform_sync)

    response = await federation_routes.sync_federation(
        request=MagicMock(),
        config_id="default",
        source="anthropic",
        user_context={"username": "admin", "is_admin": True},
        repo=repo,
        _csrf=None,
    )

    assert response["status"] == "queued"
    assert response["status_url"].startswith("/api/federation/sync/")
    await federation_routes._federation_sync_tasks[response["job_id"]]
    assert federation_routes._federation_sync_jobs[response["job_id"]]["status"] == "succeeded"
    perform_sync.assert_awaited_once()
