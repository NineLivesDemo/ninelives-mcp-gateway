import pytest
from platform_runbooks.azure_backends import build_durable_stores


def test_storage_url_requires_https_and_no_url_extras() -> None:
    with pytest.raises(ValueError, match="HTTPS"):
        build_durable_stores("http://storage.example.test")
    with pytest.raises(ValueError, match="credentials"):
        build_durable_stores("https://user:pass@storage.example.test")


def test_storage_containers_must_be_distinct() -> None:
    with pytest.raises(ValueError, match="distinct"):
        build_durable_stores(
            "https://storage.example.test", lock_container="same", audit_container="same"
        )
