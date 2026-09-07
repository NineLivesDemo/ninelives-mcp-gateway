"""Tests for removing the Anthropic federation source."""

from unittest.mock import AsyncMock, MagicMock

from fastapi import HTTPException
import pytest

import registry.api.federation_routes as federation_routes
from registry.schemas.federation_schema import (
    AnthropicServerConfig,
    FederationConfig,
)


@pytest.mark.asyncio
async def test_remove_anthropic_source_disables_and_deregisters_servers(monkeypatch):
    """Removing Anthropic clears configuration and imported server records."""
    config = FederationConfig(
        anthropic={
            "enabled": True,
            "servers": [AnthropicServerConfig(name="example/server")],
        }
    )
    repo = AsyncMock()
    repo.get_config.return_value = config
    repo.save_config.side_effect = lambda saved, _config_id: saved
    reconciliation = AsyncMock(
        return_value={"removed": ["example/server"], "removed_count": 1}
    )
    monkeypatch.setattr(
        "registry.services.federation_reconciliation.reconcile_anthropic_servers",
        reconciliation,
    )
    monkeypatch.setattr(
        "registry.repositories.factory.get_server_repository",
        lambda: MagicMock(),
    )
    monkeypatch.setattr(
        "registry.services.server_service.server_service",
        MagicMock(),
    )
    monkeypatch.setattr("registry.core.nginx_service.nginx_service", MagicMock())
    monkeypatch.setattr(federation_routes, "set_audit_action", lambda *args, **kwargs: None)

    response = await federation_routes.remove_anthropic_source(
        request=MagicMock(),
        config_id="default",
        user_context={"username": "admin", "is_admin": True},
        repo=repo,
        _csrf=None,
    )

    saved_config = repo.save_config.await_args.args[0]
    assert saved_config.anthropic.enabled is False
    assert saved_config.anthropic.servers == []
    reconciliation.assert_awaited_once()
    assert response["reconciliation"]["removed_count"] == 1


@pytest.mark.asyncio
async def test_remove_anthropic_source_requires_federation_management():
    """Non-admin callers cannot remove the source."""
    with pytest.raises(HTTPException) as exc_info:
        await federation_routes.remove_anthropic_source(
            request=MagicMock(),
            config_id="default",
            user_context={"username": "user", "is_admin": False},
            repo=AsyncMock(),
            _csrf=None,
        )

    assert getattr(exc_info.value, "status_code", None) == 403
