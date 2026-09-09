"""Managed file rendering and reconciliation primitives."""

from __future__ import annotations

import hashlib
import os
import tempfile
from dataclasses import dataclass
from pathlib import PurePosixPath

_MANAGED_ROOTS = (
    PurePosixPath("/etc/mcp-gateway"),
    PurePosixPath("/etc/platform"),
    PurePosixPath("/opt/mcp-gateway"),
    PurePosixPath("/opt/platform"),
)


@dataclass(frozen=True)
class DesiredFile:
    """Non-secret metadata and content for one managed file."""

    path: str
    content: bytes
    mode: int = 0o600


@dataclass(frozen=True)
class ObservedFile:
    """Redacted state for one file on a managed host."""

    exists: bool
    sha256: str | None
    mode: int | None


def validate_managed_path(path: str) -> str:
    """Reject paths outside the platform-managed Linux directories."""
    candidate = PurePosixPath(path)
    if not candidate.is_absolute() or ".." in candidate.parts:
        raise ValueError(f"Managed path must be an absolute safe path: {path}")
    if not any(candidate == root or root in candidate.parents for root in _MANAGED_ROOTS):
        raise ValueError(f"Path is outside managed platform roots: {path}")
    return str(candidate)


def content_sha256(content: bytes) -> str:
    """Return a deterministic digest without exposing file contents."""
    return hashlib.sha256(content).hexdigest()


def observe_file(path: str) -> ObservedFile:
    """Read file metadata and digest without returning its contents."""
    safe_path = validate_managed_path(path)
    try:
        stat_result = os.stat(safe_path)
    except FileNotFoundError:
        return ObservedFile(False, None, None)
    if not os.path.isfile(safe_path):
        raise ValueError(f"Managed path is not a regular file: {safe_path}")
    with open(safe_path, "rb") as file_handle:
        digest = hashlib.sha256(file_handle.read()).hexdigest()
    return ObservedFile(True, digest, stat_result.st_mode & 0o777)


def write_atomic(desired: DesiredFile) -> None:
    """Write a managed file atomically with the requested restrictive mode."""
    safe_path = validate_managed_path(desired.path)
    if desired.mode & 0o077:
        raise ValueError("Managed files must not be group- or world-readable")
    parent = os.path.dirname(safe_path)
    os.makedirs(parent, mode=0o700, exist_ok=True)
    descriptor, temporary_path = tempfile.mkstemp(prefix=".platform-", dir=parent)
    replaced = False
    try:
        with os.fdopen(descriptor, "wb") as file_handle:
            file_handle.write(desired.content)
            file_handle.flush()
            os.fchmod(file_handle.fileno(), desired.mode)
        os.replace(temporary_path, safe_path)
        replaced = True
    finally:
        if not replaced and os.path.exists(temporary_path):
            os.unlink(temporary_path)
