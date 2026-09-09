"""Construct Azure-backed operation stores without handling secret values."""

from __future__ import annotations

from typing import Any
from urllib.parse import urlparse

from azure.storage.blob import BlobServiceClient

from .operations import AuditSink, AzureBlobAuditSink, AzureBlobLockStore, LockStore


def _validate_storage_account_url(account_url: str) -> str:
    parsed = urlparse(account_url)
    if parsed.scheme != "https" or not parsed.netloc:
        raise ValueError("Storage account URL must be an absolute HTTPS URL")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Storage account URL must not contain credentials or URL extras")
    return account_url.rstrip("/")


def build_durable_stores(
    account_url: str,
    *,
    credential: Any | None = None,
    lock_container: str = "locks",
    audit_container: str = "audit",
) -> tuple[LockStore, AuditSink]:
    """Build lease and audit stores using an injected or managed identity credential."""
    if not lock_container or not audit_container or lock_container == audit_container:
        raise ValueError("Lock and audit containers must be distinct non-empty names")
    if credential is None:
        from azure.identity import DefaultAzureCredential

        credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
    service = BlobServiceClient(
        account_url=_validate_storage_account_url(account_url),
        credential=credential,
    )
    return (
        AzureBlobLockStore(service.get_container_client(lock_container)),
        AzureBlobAuditSink(service.get_container_client(audit_container)),
    )
