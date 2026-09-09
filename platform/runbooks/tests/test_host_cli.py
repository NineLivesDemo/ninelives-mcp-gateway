"""Tests for deterministic host CLI helpers."""

from pathlib import Path

import pytest
from platform_runbooks.host.cli import _parse_desired_file


def test_parse_desired_file_reads_content_without_returning_it(tmp_path: Path) -> None:
    source = tmp_path / "compose.yaml"
    source.write_bytes(b"services: {}\n")

    desired = _parse_desired_file(f"/opt/platform/compose/apps/compose.yaml={source}")

    assert desired.path == "/opt/platform/compose/apps/compose.yaml"
    assert desired.content == b"services: {}\n"


def test_parse_desired_file_requires_mapping_syntax() -> None:
    with pytest.raises(ValueError, match="DESTINATION=SOURCE"):
        _parse_desired_file("compose.yaml")
