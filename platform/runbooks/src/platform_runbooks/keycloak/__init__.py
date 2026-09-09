"""Read-only Keycloak discovery and planning helpers for platform automation."""

from .discovery import KeycloakAdminClient, KeycloakConfigurationError, KeycloakSnapshot
from .plan import (
    ClientExpectation,
    KeycloakExpectation,
    KeycloakPlan,
    PlanChange,
    build_plan,
)

__all__ = [
    "ClientExpectation",
    "KeycloakAdminClient",
    "KeycloakConfigurationError",
    "KeycloakExpectation",
    "KeycloakPlan",
    "KeycloakSnapshot",
    "PlanChange",
    "build_plan",
]
