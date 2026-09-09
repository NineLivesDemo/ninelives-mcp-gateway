"""Tests for deny-by-default Automation job contracts."""

import pytest
from platform_runbooks.automation import RunbookRequest, build_job, validate_request


def test_read_only_job_is_allowlisted_and_secret_free() -> None:
    job = build_job(RunbookRequest("verify", "apps", "git-abc123"))

    assert job.name == "platform-verify-apps"
    assert job.vm_name == "vm-platform-apps"
    assert not job.requires_confirmation
    assert "secret" not in repr(job).lower()


def test_apply_requires_approved_plan_and_exact_confirmation() -> None:
    with pytest.raises(ValueError, match="approved plan ID"):
        validate_request(RunbookRequest("apply", "apps", "git-abc123"))
    with pytest.raises(ValueError, match="exact confirmation phrase"):
        validate_request(RunbookRequest("apply", "apps", "git-abc123", "plan-1", "apply"))

    job = build_job(RunbookRequest("apply", "apps", "git-abc123", "plan-1", "APPLY"))

    assert job.requires_confirmation
    assert job.approved_plan_id == "plan-1"


def test_keycloak_bootstrap_is_never_an_allowed_apply() -> None:
    with pytest.raises(ValueError, match="use keycloak-reconcile"):
        validate_request(RunbookRequest("apply", "keycloak", "git-abc123", "plan-1", "APPLY"))
    with pytest.raises(ValueError, match="existing-realm preflight"):
        validate_request(
            RunbookRequest("keycloak-reconcile", "keycloak", "git-abc123", "plan-1", "APPLY")
        )

    job = build_job(
        RunbookRequest("keycloak-reconcile", "keycloak", "git-abc123", "plan-1", "APPLY", True)
    )

    assert job.requires_confirmation


def test_unknown_role_and_approval_fields_fail_closed() -> None:
    with pytest.raises(ValueError, match="Unknown platform role"):
        validate_request(RunbookRequest("plan", "all", "git-abc123"))
    with pytest.raises(ValueError, match="only valid for mutation"):
        validate_request(RunbookRequest("plan", "apps", "git-abc123", "plan-1"))


def test_registry_schema_verification_is_read_only_and_apps_only() -> None:
    job = build_job(RunbookRequest("registry-schema-verify", "apps", "git-abc123"))
    assert not job.requires_confirmation
    with pytest.raises(ValueError, match="only valid for the apps role"):
        validate_request(RunbookRequest("registry-schema-verify", "keycloak", "git-abc123"))