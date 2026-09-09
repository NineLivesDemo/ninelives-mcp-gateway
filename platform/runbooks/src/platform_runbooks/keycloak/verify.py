"""Read-only verification of the documented Keycloak contract."""

from __future__ import annotations

from dataclasses import dataclass

from .discovery import KeycloakSnapshot
from .plan import KeycloakExpectation, KeycloakPlan, build_plan

_REQUIRED_OIDC_FIELDS = (
    "issuer",
    "authorization_endpoint",
    "token_endpoint",
    "registration_endpoint",
    "jwks_uri",
)


@dataclass(frozen=True)
class VerificationCheck:
    """One deterministic verification result."""

    name: str
    passed: bool
    detail: str


@dataclass(frozen=True)
class VerificationResult:
    """Read-only verification output suitable for an automation job."""

    checks: tuple[VerificationCheck, ...]
    plan: KeycloakPlan

    @property
    def passed(self) -> bool:
        """Return whether every verification check passed."""
        return all(check.passed for check in self.checks)


def verify_snapshot(
    snapshot: KeycloakSnapshot,
    expectation: KeycloakExpectation,
) -> VerificationResult:
    """Verify OIDC metadata and the documented non-secret contract."""
    plan = build_plan(snapshot, expectation)
    checks: list[VerificationCheck] = []
    checks.append(
        VerificationCheck(
            "desired_state",
            plan.is_noop,
            "live state matches the documented contract"
            if plan.is_noop
            else f"{len(plan.changes)} desired-state difference(s) found",
        )
    )

    metadata = snapshot.oidc_metadata
    for field in _REQUIRED_OIDC_FIELDS:
        value = metadata.get(field)
        checks.append(
            VerificationCheck(
                f"oidc.{field}",
                isinstance(value, str) and bool(value),
                "present" if isinstance(value, str) and value else "missing",
            )
        )

    methods = metadata.get("code_challenge_methods_supported", [])
    checks.append(
        VerificationCheck(
            "oidc.pkce.s256",
            isinstance(methods, list) and "S256" in methods,
            "S256 supported" if isinstance(methods, list) and "S256" in methods else "S256 missing",
        )
    )
    checks.append(
        VerificationCheck(
            "oidc.dcr",
            isinstance(metadata.get("registration_endpoint"), str),
            "registration endpoint published"
            if isinstance(metadata.get("registration_endpoint"), str)
            else "registration endpoint missing",
        )
    )
    return VerificationResult(tuple(checks), plan)
