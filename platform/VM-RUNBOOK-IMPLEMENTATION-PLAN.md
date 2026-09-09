# VM Runbook Implementation Plan

**Status:** Draft  
**Created:** 2026-09-09  
**Scope:** Private platform VMs in `platform-pilot`

## Purpose

The private VM deployment required repeated host-specific configuration, renderer changes, service restarts, and Bastion sessions. This plan defines a Python-first configuration and operations layer so VM work is repeatable, unit-testable, auditable, and safe to apply more than once.

The target is not to hide the same ad hoc shell commands behind Azure Automation. The target is one tested Python configuration module with multiple execution paths: local development, Bastion-assisted operation, an extension-based Hybrid Runbook Worker, and an Azure Automation runbook that orchestrates the operation.

## Current baseline

The platform Bicep already provisions an Azure Automation Account with a system-assigned managed identity in `rg-ops`. It does not currently provision runbooks, worker groups, worker extensions, runbook packages, or runbook-specific RBAC.

The VMs are private and have no public IPs. Bastion Standard is the current preferred operator access path. Azure VM Run Command remains a fallback control channel and must not become the permanent configuration mechanism.

| VM | Private address | Role | Primary service unit |
| --- | --- | --- | --- |
| `vm-platform-edge` | `10.60.1.4` | APISIX and Cloudflare Tunnel | `platform-edge.service` |
| `vm-platform-etcd` | `10.60.2.4` | Private mTLS etcd | `platform-etcd.service` |
| `vm-platform-openbao` | `10.60.3.4` | OpenBao Raft and Azure Key Vault auto-unseal | `platform-openbao.service` |
| `vm-platform-apps` | `10.60.4.4` | Registry, auth-server, and MCP gateway | `platform-apps.service` |
| `vm-platform-keycloak` | `10.60.5.4` | Keycloak backed by PostgreSQL | `platform-keycloak.service` |

## Design decision

Python is the default implementation language for configuration, validation, state comparison, and verification. Bash is limited to unavoidable host bootstrap or very small systemd glue. Azure Automation is an orchestration and scheduling layer, not the source of configuration truth.

Only extension-based Hybrid Runbook Workers are in scope. The retired agent-based User Hybrid Runbook Worker must not be deployed. The [Microsoft migration guidance](https://learn.microsoft.com/en-us/azure/automation/migrate-existing-agent-based-hybrid-worker-to-extension-based-workers) is the compatibility reference.

The same Python package should be able to run in these modes:

| Mode | Purpose | Mutation policy |
| --- | --- | --- |
| Local workstation | Unit tests, rendering, schema validation, and dry runs | No live mutation by default |
| Bastion plus SSH | Break-glass investigation and first manual rollout | Explicit operator approval |
| Extension-based Hybrid Worker | Local access to files, Docker, systemd, and private services | Approved runbook job only |
| Azure Automation cloud runbook | Scheduling, orchestration, Azure API calls, and reporting | Read-only by default; mutations require explicit confirmation |
| Azure VM Run Command | Narrow fallback when worker or SSH access is unavailable | Emergency-only and fully logged |

## Target package shape

The implementation should live under `platform/runbooks/` and be independently testable without Azure, Docker, or a live VM.

```text
platform/runbooks/
├── pyproject.toml
├── src/platform_runbooks/
│   ├── cli.py
│   ├── models.py
│   ├── manifest.py
│   ├── planner.py
│   ├── executor.py
│   ├── verification.py
│   ├── redaction.py
│   ├── azure_control_plane.py
│   ├── host/
│   │   ├── files.py
│   │   ├── services.py
│   │   └── containers.py
│   └── roles/
│       ├── edge.py
│       ├── etcd.py
│       ├── openbao.py
│       ├── apps.py
│       └── keycloak.py
└── tests/
    ├── unit/
    ├── contract/
    └── integration/
```

The host adapters must use explicit argument lists, timeouts, and checked exit codes when a system command is unavoidable. Configuration values and secret contents must never be placed on command lines or emitted in logs.

## Common execution contract

Every operation must implement the same lifecycle:

1. Load a versioned, non-secret desired-state manifest.
2. Validate role, VM identity, paths, image digests, schemes, ports, and allowed mutations.
3. Read current state without exposing secret values.
4. Produce a structured plan containing changes, dependencies, and risk.
5. Require an explicit apply decision for mutations.
6. Apply changes atomically and idempotently.
7. Restart only the affected service and wait for its health condition.
8. Verify local and externally observable behavior.
9. Emit redacted audit data with correlation ID, actor, VM, version, action, result, and duration.

The default behavior is `plan` or read-only verification. Missing configuration, an unknown VM role, a stale manifest, an unavailable lock, or an ambiguous target must fail closed.

## Runbook catalog

The first release should use a small number of composable runbooks rather than one script per command.

### `platform-health`

Read-only checks for all VMs or a selected role: Azure resource state, VM agent state, disk capacity, certificate expiry metadata, secret-sync status, systemd status, Docker/container health, local health endpoints, and expected listening addresses. It must never print environment files, tokens, private keys, or full container configuration.

### `platform-plan`

Compares the desired manifest with the selected VM and returns a deterministic diff. It must support `all`, `edge`, `etcd`, `openbao`, `apps`, and `keycloak` targets and must not modify the host.

### `platform-apply`

Applies one selected role at a time. It must reject broad unbounded operations, acquire a distributed lock, validate the plan version, apply the smallest required change, and verify health before releasing the lock.

### `platform-verify`

Runs post-apply checks and the acceptance probes for the selected role. It should be safe to run on a schedule and should report drift without attempting repair.

### `keycloak-reconcile`

Performs targeted, idempotent realm/client/group/scope reconciliation through the Keycloak administration API. It must never rerun the full initialization script against an existing realm or regenerate client secrets implicitly.

### `edge-route-apply`

Applies the rendered APISIX route only after the target application and Keycloak health checks pass. It must validate public host and forwarded-HTTPS metadata before changing traffic-bearing routes.

## Implementation phases

### Phase 0: Establish the execution boundary

- Confirm the supported extension-based Hybrid Worker model and its required VM extension, worker group, outbound connectivity, and package/runtime requirements.
- Decide whether workers are installed on each VM or on a dedicated private operations VM. Per-VM workers provide direct Docker/systemd access but increase the installed management surface; a dedicated worker is preferable when Azure API orchestration is sufficient.
- Define the Automation Account managed-identity permissions with least privilege. Separate read-only health permissions from mutation permissions.
- Define the audit destination and retention. Do not assume the existing Log Analytics workspace is available for Automation job output until it is inventoried.
- Define the concurrency lock and stale-lock recovery behavior before enabling mutations.

### Phase 1: Build the Python core

- Create the package, manifest schema, role model, redaction helpers, structured result types, and CLI.
- Implement pure render and validation functions first.
- Add host adapters behind interfaces so unit tests do not invoke Docker, systemd, SSH, or Azure.
- Add `plan`, `apply`, and `verify` commands with explicit target and version arguments.
- Add test fixtures representing the current edge, etcd, OpenBao, apps, and Keycloak configurations without secret values.

### Phase 2: Implement read-only health

- Implement `platform-health` and `platform-verify` with no mutation capability in the first deployment.
- Run it manually through Bastion and compare its output with the known-good current deployment.
- Add contract tests for redaction, failure states, service dependencies, and private-only network expectations.
- Establish a baseline report so later `platform-plan` runs can distinguish expected drift from accidental drift.

### Phase 3: Implement per-role planning and apply

- Start with the lowest-risk role, etcd, using configuration hashes and health verification.
- Add OpenBao with explicit safeguards around Raft data, auto-unseal, and token-bearing files.
- Add Keycloak with targeted configuration reconciliation and no implicit realm bootstrap.
- Add the application VM with image digest, environment rendering, volume ownership, and Compose health checks.
- Add the edge VM last because route changes affect public traffic; require backend readiness before applying a route.
- Keep service restarts role-scoped and wait for health rather than sleeping for a fixed duration.

### Phase 4: Package for supported execution

- Package the same Python module for local execution and the extension-based Hybrid Worker runtime.
- Pin dependencies and document the supported Python runtime for the Automation environment.
- Store only immutable package/artifact references in runbook parameters; do not pass secrets or arbitrary commands.
- Add runbook job correlation, timeout, retry, cancellation, and redacted output handling.

### Phase 5: Automate orchestration

- Add a read-only scheduled `platform-health` job.
- Add a manually triggered `platform-plan` job that produces an approval artifact.
- Add a mutation job that accepts only a role, approved plan ID, artifact version, and explicit confirmation.
- Sequence dependencies as `etcd -> openbao -> keycloak -> apps -> edge` when a full platform apply is required, while allowing safe role-scoped operations.
- Make concurrent applies fail closed rather than queueing unreviewed changes.

### Phase 6: Operational acceptance

- Prove a no-op plan against the current live state.
- Prove a controlled change on one non-production or low-risk role, followed by verification.
- Prove a failed apply leaves the previous valid configuration intact.
- Prove worker loss, Azure API timeout, service startup failure, stale lock, and invalid manifest handling.
- Prove public OAuth login, callback, session, and logout remain healthy after edge and application changes.
- Document the operator workflow and retain Bastion as break-glass access.

## Testing strategy

Unit tests must cover manifest parsing, validation, planning, redaction, idempotency decisions, dependency ordering, lock behavior, and all role-specific renderers. Host and Azure boundaries must be mocked or replaced with deterministic fakes.

Contract tests must assert that generated files contain no unresolved placeholders, secrets are never returned in plans or errors, file writes use restrictive permissions, public HTTPS metadata is preserved, and mutation targets are allowlisted.

Integration tests must run against disposable or explicitly designated platform fixtures and cover Docker/systemd adapters, Keycloak reconciliation, APISIX route application, and health verification. Live production-like runs must begin with read-only mode and require an explicit apply approval.

## Security requirements

- Use the Automation Account managed identity and narrowly scoped RBAC; do not add subscription-wide contributor access.
- Use Key Vault or protected VM files for secrets; never pass secret values as runbook parameters, SSH arguments, subprocess arguments, or log content.
- Treat all runbook parameters and registry/configuration data as untrusted input.
- Require human confirmation for every mutating or destructive operation.
- Use an allowlist for VM roles, paths, services, images, and permitted operations.
- Enforce timeouts, bounded retries, and explicit error reporting.
- Keep audit records durable and attributable to the initiating actor.
- Do not deploy retired agent-based Hybrid Workers.

## Definition of done

- The current platform can be represented by a non-secret desired-state manifest.
- A read-only plan produces no changes against the known-good deployment.
- Every mutation is implemented in tested Python and is safe to rerun.
- Standard configuration no longer requires an operator to adapt shell commands interactively.
- Supported extension-based worker execution is proven for the selected topology.
- Azure Automation jobs are least-privilege, redacted, auditable, concurrency-safe, and deny-by-default.
- Role-scoped health and public acceptance checks pass after an apply.
- Bastion remains available for break-glass access, but is no longer required for routine configuration.

## Open decisions

- Select per-VM versus dedicated private worker topology.
- Select the immutable artifact store and promotion process for the Python package.
- Select the lock and audit backends.
- Confirm the supported Automation Python runtime and dependency packaging method.
- Decide which configuration changes require human approval versus read-only scheduled detection.
