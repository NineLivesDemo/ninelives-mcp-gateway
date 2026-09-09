"""Tests for secret-safe Keycloak credential handling."""

import httpx
from platform_runbooks.keycloak.credentials import request_admin_token


def test_request_admin_token_does_not_require_cli_arguments() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path.endswith("/realms/master/protocol/openid-connect/token")
        assert request.content
        return httpx.Response(200, json={"access_token": "token-value"})

    token = request_admin_token(
        "https://idp.example.test",
        "admin",
        "password",
        transport=httpx.MockTransport(handler),
    )

    assert token == "token-value"
