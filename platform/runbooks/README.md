# Platform runbooks

This directory contains the Azure-specific read-only discovery, planning, verification, and approval boundaries for the private VM platform. The application and Keycloak behavior remain defined by `docs/`; these modules only execute platform operations against that contract.

## Current safety boundary

The default operations are read-only: `discover`, `plan`, `verify`, and `registry-schema-verify`. The schema check validates supplied Registry scope documents and never writes to MongoDB. Host mutation requires an immutable plan fingerprint, a scoped lock, an approved plan ID, and the exact confirmation phrase `APPLY`.

The initial `keycloak/setup/init-keycloak.sh` script is not an Automation operation. It creates the predefined clients and regenerates their client secrets. Existing realms must use the targeted `keycloak-reconcile` operation after an existing-realm preflight. Missing predefined clients fail closed instead of triggering bootstrap behavior.

## Local commands

Run the host discovery and planning CLI from the repository root with the runbook source on `PYTHONPATH`:

```bash
PYTHONPATH=platform/runbooks/src uv run python -m platform_runbooks.host.cli discover --role apps --no-health
PYTHONPATH=platform/runbooks/src uv run python -m platform_runbooks.host.cli plan --role keycloak --no-health --desired-file /opt/platform/compose/keycloak/compose.yaml=/path/to/compose.yaml
```

The output is redacted and deterministic. File contents, environment values, tokens, and response bodies are never included in plans or health results.

## Building the package

Build an immutable source archive for the Hybrid Runbook Worker with:

```bash
uv run python platform/runbooks/package.py platform-read-only-runbook.zip
```

The command emits the archive SHA-256. The archive includes the top-level `runbook.py` entrypoint and the `platform_runbooks` source package. The entrypoint accepts only validated environment inputs (`PLATFORM_OPERATION`, `PLATFORM_ROLE`, and `PLATFORM_ARTIFACT_VERSION`, plus approval fields for mutation requests). It executes only the read-only `discover`, `plan`, and `verify` operations on the local worker; mutation requests remain disabled until durable lock and audit backends are configured. Publish the archive to an approved artifact store and pass its immutable URI and digest to Bicep:

```text
deployPlatformRunbook = true
platformRunbookContentUri = <immutable artifact URI>
platformRunbookContentVersion = <archive digest or release version>
```

The Bicep default is `deployPlatformRunbook = false`; publishing is never enabled implicitly.

## Execution model

Azure Automation supplies scheduling, identity, job metadata, and approval workflow. An extension-based Hybrid Runbook Worker supplies access to private VM files, systemd, Docker, and private health endpoints. The runbook package does not accept arbitrary shell commands or secret values as parameters. Bastion remains the break-glass path.

The current Bicep change publishes the read-only Automation runbook resource only when explicitly enabled. Worker extension deployment, durable lock storage, durable audit storage, package promotion, and production acceptance remain separate rollout steps.
## Hybrid Worker extension deployment

The subscription Bicep template has a separate opt-in switch for the extension-based Linux workers. When `deployHybridWorkers = true`, it installs `HybridWorkerExtension` on the five existing private service VMs and points each extension at the Automation Account's `automationHybridServiceUrl`:

```text
deployHybridWorkers = true
```

The extension uses publisher `Microsoft.Azure.Automation.HybridWorker`, type `HybridWorkerForLinux`, and handler version `1.1`. The VM names and resource-group scopes are fixed in Bicep so the deployment cannot target an arbitrary host. This flag assumes the VMs already exist; it does not create or mutate VM instances. The extension rollout must still be followed by worker registration and read-only job verification before any mutation operation is approved.
## Durable mutation controls

`platform_runbooks.operations` includes `AzureBlobLockStore`, which uses a short Azure Blob lease on a hashed role/VM key, and `AzureBlobAuditSink`, which writes one immutable, fixed-shape JSON blob per operation. Both accept an injected credential and storage container client; they never accept secrets as job parameters or write request payloads. Configure the storage account and containers through infrastructure and grant the Automation identity only the required blob lease and create/write permissions before wiring these adapters into a production runbook.

The host executor already consumes the `LockStore` and `AuditSink` interfaces, so switching from the in-memory test implementations to these Azure-backed adapters does not change the approval contract. Lease durations are bounded to Azure's 15-60 second acquisition range; a renewal loop must be added before running operations that can exceed the lease duration.
The `build_durable_stores()` factory in `platform_runbooks.azure_backends` validates the HTTPS storage endpoint and uses `DefaultAzureCredential` when no credential is injected. The runbook should receive only `PLATFORM_OPERATIONS_STORAGE_ACCOUNT_URL`; container names remain fixed as `locks` and `audit`. Configure private endpoint/DNS access before enabling production mutation jobs.

For the Registry schema check, set `PLATFORM_OPERATION=registry-schema-verify` and `PLATFORM_ROLE=apps`. On the Hybrid Worker, the default mode reads `/etc/platform/secrets/raw/mongodb-connection-string` and queries Atlas with the Python `pymongo` driver; it projects only `_id`, `group_mappings`, and `ui_permissions`. For offline tests, set `PLATFORM_REGISTRY_SCOPE_DOCUMENTS` to a JSON array instead. The output contains only validity, count, required scope IDs, collection name, and redacted validation errors.
