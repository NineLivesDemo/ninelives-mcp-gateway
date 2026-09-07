from unittest.mock import patch

from registry.schemas.federation_schema import AnthropicServerConfig
from registry.services.federation.anthropic_client import AnthropicFederationClient


def _catalog_entry(name: str) -> dict:
    return {
        "server": {
            "name": name,
            "description": f"{name} description",
            "version": "1.0.0",
            "remotes": [{"type": "streamable-http", "url": f"https://{name}.example.com/mcp"}],
        },
        "_meta": {},
    }


def test_empty_server_filter_fetches_paginated_catalog() -> None:
    client = AnthropicFederationClient("https://registry.modelcontextprotocol.io")
    pages = [
        {
            "servers": [_catalog_entry("example/one")],
            "metadata": {"nextCursor": "cursor-1"},
        },
        {
            "servers": [_catalog_entry("example/two")],
            "metadata": {"nextCursor": None},
        },
    ]

    with patch.object(client, "_make_request", side_effect=pages) as request:
        servers = client.fetch_all_servers([])

    assert [server["server_name"] for server in servers] == ["example/one", "example/two"]
    assert request.call_args_list[0].kwargs["params"] == {"limit": 100}
    assert request.call_args_list[1].kwargs["params"] == {"limit": 100, "cursor": "cursor-1"}


def test_explicit_server_filter_does_not_use_catalog_listing() -> None:
    client = AnthropicFederationClient("https://registry.modelcontextprotocol.io")
    server = _catalog_entry("example/one")

    with patch.object(client, "fetch_server", return_value=server["server"]) as fetch_server:
        servers = client.fetch_all_servers(
            [AnthropicServerConfig(name="example/one")],
        )

    assert len(servers) == 1
    fetch_server.assert_called_once()
