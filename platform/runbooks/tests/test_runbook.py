import importlib.util
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location(
    "platform_runbook_entrypoint", Path(__file__).parents[1] / "runbook.py"
)
assert _spec and _spec.loader
runbook = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(runbook)


def test_read_only_dispatch_routes_supported_operations(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(runbook, "_discover", lambda role: {"role": role})
    monkeypatch.setattr(runbook, "_plan", lambda role: {"role": role})
    monkeypatch.setattr(runbook, "_verify", lambda role: ({"role": role}, True))

    assert runbook._execute_read_only("discover", "apps") == ({"role": "apps"}, True)
    assert runbook._execute_read_only("plan", "apps") == ({"role": "apps"}, True)
    assert runbook._execute_read_only("verify", "apps") == ({"role": "apps"}, True)


def test_mutation_dispatch_remains_disabled() -> None:
    with pytest.raises(RuntimeError, match="durable lock and audit"):
        runbook._execute_read_only("apply", "apps")
