"""Tests for deterministic runbook packaging."""

from pathlib import Path
from zipfile import ZipFile

from package import build_package


def test_build_package_contains_source_only(tmp_path: Path) -> None:
    source = tmp_path / "src" / "platform_runbooks"
    source.mkdir(parents=True)
    (source / "__init__.py").write_text("VALUE = 1\n")
    (source / "secret.txt").write_text("not included\n")
    (source / "__pycache__").mkdir()
    (source / "__pycache__" / "bad.py").write_text("not included\n")
    output = tmp_path / "runbooks.zip"

    digest = build_package(output, source)

    assert len(digest) == 64
    with ZipFile(output) as archive:
        assert archive.namelist() == ["platform_runbooks/__init__.py"]
