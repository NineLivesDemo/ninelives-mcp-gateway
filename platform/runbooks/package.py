"""Build an immutable source archive for the Hybrid Runbook Worker."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

_RUNBOOK_ROOT = Path(__file__).parent
_SOURCE_ROOT = _RUNBOOK_ROOT / "src" / "platform_runbooks"


def build_package(output: Path, source_root: Path = _SOURCE_ROOT) -> str:
    """Create a deterministic source-only archive and return its SHA-256."""
    files = sorted(path for path in source_root.rglob("*.py") if "__pycache__" not in path.parts)
    if source_root == _SOURCE_ROOT:
        files.append(_RUNBOOK_ROOT / "runbook.py")
    if not files:
        raise ValueError("Runbook source tree is empty")
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
        for path in files:
            relative = (
                path.relative_to(_RUNBOOK_ROOT)
                if path == _RUNBOOK_ROOT / "runbook.py"
                else path.relative_to(source_root.parent)
            )
            archive_name = str(relative).replace("\\", "/")
            info = ZipInfo(archive_name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes())
    return hashlib.sha256(output.read_bytes()).hexdigest()


def main() -> int:
    """Build a runbook package and emit machine-readable metadata."""
    parser = argparse.ArgumentParser(description="Build a Hybrid Worker runbook package")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    digest = build_package(args.output)
    print(json.dumps({"path": str(args.output), "sha256": digest}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
