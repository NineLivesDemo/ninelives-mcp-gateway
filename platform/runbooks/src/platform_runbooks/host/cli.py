"""Read-only host discovery and planning CLI."""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict
from pathlib import Path

from platform_runbooks.manifest import get_role_manifest

from .discovery import SubprocessRunner, discover_role
from .files import DesiredFile
from .plan import plan_host
from .services import DesiredService


def _parse_desired_file(value: str) -> DesiredFile:
    """Read one local desired file using the managed Linux destination as its key."""
    try:
        destination, source = value.split("=", 1)
    except ValueError as error:
        raise ValueError("Desired file must use DESTINATION=SOURCE syntax") from error
    if not destination or not source:
        raise ValueError("Desired file destination and source are required")
    return DesiredFile(destination, Path(source).read_bytes())


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Read-only platform VM discovery and planning")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("discover", "plan"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument(
            "--role", required=True, choices=("apps", "keycloak", "edge", "etcd", "openbao")
        )
        subparser.add_argument("--no-health", action="store_true")
        if command == "plan":
            subparser.add_argument(
                "--desired-file",
                action="append",
                default=[],
                metavar="DESTINATION=SOURCE",
                help="repeat for each non-secret desired file",
            )
    return parser


def main() -> int:
    """Run a read-only discovery or host planning operation."""
    args = _parser().parse_args()
    manifest = get_role_manifest(args.role)
    snapshot = discover_role(
        manifest,
        SubprocessRunner(),
        probe=not args.no_health,
    )
    result: dict[str, object] = {
        "manifest": asdict(manifest),
        "snapshot": asdict(snapshot),
    }
    if args.command == "plan":
        desired_files = tuple(_parse_desired_file(item) for item in args.desired_file)
        host_plan = plan_host(
            manifest.role,
            manifest.vm_name,
            desired_files,
            snapshot.files,
            (DesiredService(manifest.systemd_unit),),
            snapshot.services,
        )
        result["plan"] = asdict(host_plan)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
