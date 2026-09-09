# Azure Registry VM migration handoff

**Last updated:** 2026-09-09 16:52 UTC  
**Repository:** `NineLivesDemo/ninelives-mcp-gateway`  
**Working directory:** `/home/rpl/Projects/NLAI/mcp-gateway-registry`  
**Subscription:** `Azure subscription 1` (`24595c03-870c-4a3e-93b3-51ec93c246bf`)  
**Region:** `westus3`  
**Environment:** `platform-pilot`  
**VNet:** `vnet-platform-pilot` (`10.60.0.0/16`)

This document is the operational source for the next agent. It records what was
deployed, what was changed, what was verified, what remains unfinished, and
which actions are safe. Do not infer that a source-code change has reached an
existing VM: Azure rejects changes to an existing VM's `osProfile.customData`.

## Executive state

The Registry application tier has been migrated from ACA capacity to private
VMs. ACA remains present but is not part of the target operating model. The VM
infrastructure is deployed. OpenBao is initialized and usable. Keycloak is running with the
persisted `mcp-gateway` realm initialized and verified. The Registry,
auth-server, and MCP gateway Compose stack is running and healthy after
correcting shared-volume ownership. Azure Bastion Standard is deployed in the
platform VNet with native SSH tunneling enabled for operator and agent access.

The last confirmed application state was:

- `platform-apps.service`: active.
- `apps-auth-server-1`: healthy.
- `apps-mcpgw-server-1`: healthy.
- `apps-registry-1`: healthy.
- `apps-auth-server-1`: healthy.
- `apps-mcpgw-server-1`: healthy.
- Registry health returned HTTP 200 after the ownership repair.
- Bastion SSH reached the application VM and confirmed the Registry health endpoint.
- Keycloak's persisted application realm, clients, groups, scopes, mappers, and
  administrator were verified over Bastion SSH.
- The M2M client-credentials flow returned a token with the expected
  `mcp-gateway` audience and access scopes.
- APISIX now routes the public Registry and Keycloak hostnames to the private VM
  origins instead of ACA. The Registry route explicitly sets
  `X-Forwarded-Proto: https`, `X-Forwarded-Port: 443`, and the public
  `X-Forwarded-Host`; the previous ACA origin configuration is preserved on the
  edge VM at `/etc/platform/config/edge-origin.env.aca-rollback`.
- The Registry's auth subrequest marker was normalized in Key Vault and in the
  application secret renderer. Unauthenticated `/api/auth/me` now returns HTTP
  401 instead of the previous HTTP 500.
- Keycloak now publishes the canonical HTTPS issuer even for internal VM
  requests. A private end-to-end browser OAuth flow completed through login,
  callback, secure session creation, and `/api/auth/me` returned HTTP 200.
- Public OIDC discovery, Registry health, provider discovery, and the OAuth
  authorization redirect are working. A public browser-style sign-in with valid
  Keycloak credentials completed through the login form, authorization-code
  callback, secure session creation, and `/api/auth/me` returned HTTP 200. A
  fresh public token POST with missing or invalid client credentials reaches
  Keycloak and returns its expected HTTP 401 `invalid_client`; the previous
  Cloudflare HTTP 403/1010 was not reproduced.
- Public `/api/auth/logout` clears the local Registry session correctly
  (`/api/auth/me` returns HTTP 401 afterward), and Keycloak now completes the
  IdP logout redirect with HTTP 302 to the public `/logout` page.
- The live `mcp-gateway-web` client has the exact
  `https://registry-github.adriangarciacruz.com/logout` post-logout URI, and
  its client secret was preserved. The Registry APISIX route now explicitly
  forwards public HTTPS metadata; without that route setting, the HTTP private
  origin caused the Registry to generate an invalid `http://` logout URI.

The next agent should not repeat the OpenBao recovery or secret-seeding work.
Use Azure Bastion native SSH for agent-operated VM access. Azure VM Run Command
remains the fallback control channel.

## Deployment lessons and automation recommendation

This deployment exposed a recurring boundary: Azure resource provisioning,
private-VM configuration, and application initialization are different
lifecycles. Azure VM `osProfile.customData` is effectively immutable after
creation, so changes made only to bootstrap shell scripts do not repair an
existing VM. Generated artifacts also have to be rebuilt and explicitly
applied to the running host.

The recommended future split is:

- Keep Bicep responsible for Azure resources, networking, identities, RBAC, and
  private access boundaries.
- Keep a small VM-local configuration layer responsible for files, Docker
  Compose, systemd, certificates, permissions, and service restarts. Make
  Python the default implementation language so renderers and configuration
  decisions can be unit-tested and exercised with mocked host boundaries. Use
  schema validation, atomic mode-600 writes, and explicit dry-run/apply modes;
  use shell only as minimal systemd or package glue.
- Use Azure Automation Python runbooks for control-plane orchestration:
  resource health checks, Key Vault and managed-identity operations, deployment
  sequencing, controlled service actions, drift detection, and operator-facing
  reports.

Azure Automation runbooks should not be treated as a direct replacement for
VM bootstrap shell scripts. A cloud runbook cannot access private VM files,
Docker, or systemd without an extension-based Hybrid Runbook Worker, Azure VM
Run Command, or another explicitly approved execution channel. Runbooks also
introduce separate Python runtime/package constraints, job timeouts,
concurrency, and dependency-version management. For this platform, use an
extension-based Hybrid Runbook Worker only if runbooks must execute local VM
configuration; otherwise, keep local configuration in a versioned VM artifact
and let the runbook orchestrate it. The retired agent-based User Hybrid
Runbook Worker must not be used; existing workers must follow Microsoft's
[migration guidance](https://learn.microsoft.com/en-us/azure/automation/migrate-existing-agent-based-hybrid-worker-to-extension-based-workers).

The practical alternatives are therefore explicit:

- Bastion or SSH followed by a versioned Bash entry point is acceptable for
  narrowly scoped VM changes and is the simplest recovery path.
- Azure VM Run Command followed by Bash is a fallback control channel, not a
  substitute for a durable deployment artifact.
- An extension-based Hybrid Runbook Worker followed by a versioned Python or
  Bash entry point can remove the operator SSH step, but it does not remove
  the need for local execution, validation, logging, and idempotency.

The immediate improvement is to stop adapting long commands interactively:
keep a Python configuration entry point and its tests in the repository, make
it validate its inputs before changing anything, pass secrets through managed
identity or protected files, and make each operation safe to rerun. The same
tested Python module can then run locally, through an extension-based Hybrid
Runbook Worker, or behind an Azure Automation runbook without changing the VM
configuration logic.

Any runbook adopted here should use the platform managed identity, avoid
secrets on parameters or command lines, use SDKs rather than invoking `az` or
shell commands, enforce idempotency and a concurrency lock, support dry-run
output, emit redacted audit records, and fail closed on missing or ambiguous
configuration. A good first candidate is a read-only Python platform-health
runbook, followed by a narrowly scoped configuration-apply runbook after its
local execution boundary is selected.

The detailed implementation plan is
[VM-RUNBOOK-IMPLEMENTATION-PLAN.md](VM-RUNBOOK-IMPLEMENTATION-PLAN.md).

## Deployed resource map

| Role | Resource group | VM/resource | Private address | Current state |
| --- | --- | --- | --- | --- |
| Network | `rg-network` | `vnet-platform-pilot` | `10.60.0.0/16` | Deployed |
| Access | `rg-network` | `bas-vnet-platform-pilot` | `20.168.52.33` | Azure Bastion Standard, tunneling enabled |
| Edge | `rg-edge` | `vm-platform-edge` | `10.60.1.4` | Existing VM reused |
| etcd | `rg-etcd` | `vm-platform-etcd` | `10.60.2.4` | Existing VM reused |
| OpenBao | `rg-openbao` | `vm-platform-openbao` | `10.60.3.4` | Running and healthy |
| Registry tier | `rg-mcp-registry` | `vm-platform-apps` | `10.60.4.4` | Running and healthy |
| Keycloak | `rg-mcp-keycloak` | `vm-platform-keycloak` | `10.60.5.4` | Running and issuer verified |
| Operations | `rg-ops` | `kvplatformrtsxkr2fmvx42` | Azure Key Vault | Deployed |
| ACR | `rg-ops` | `cr4bqvj62ztmxmi` | `cr4bqvj62ztmxmi.azurecr.io` | Existing ACR |

The application, Keycloak, and OpenBao VMs have no public IPs. Do not add public
IPs merely to simplify administration. The Bastion public IP is a managed access
endpoint, not a VM public IP. The edge VM remains the public ingress boundary
through the existing tunnel and APISIX deployment.

## Intended architecture

```text
Browser
  -> existing Cloudflare Tunnel
  -> APISIX on vm-platform-edge (10.60.1.4)
  -> Registry VM (10.60.4.4:8080)
  -> Registry/auth-server/MCP gateway Compose services

Operator or agent
  -> Azure Bastion Standard (managed public endpoint)
  -> private VM SSH (no VM public IP)

Registry VM
  -> Keycloak VM (10.60.5.4)
  -> OpenBao VM (10.60.3.4:8200, private TLS)
  -> external MongoDB
  -> external PostgreSQL for Keycloak
  -> ACR/MongoDB/embeddings/remote MCP services through NAT egress
```

The Registry VM does not host stdio MCP servers. The Registry, auth-server, and
MCP gateway run as separate containers. Keycloak runs on its own VM using the
official Quay image pinned by digest. OpenBao runs as a single-node Raft
deployment with Azure Key Vault auto-unseal.

## Exact deployment parameters

The temporary deployment parameter file used for the successful VM deployment
was `.scratchpad/deploy-main.apps-vm.bicepparam`. Its important values were:

```text
environmentName             = platform-pilot
location                    = westus3
deployFoundationVms         = false
deployRuntimeAccess         = true
deployApps                  = false
deployAppVm                 = true
deployKeycloakVm            = true
appVmPrivateIpAddress       = 10.60.4.4
keycloakVmPrivateIpAddress  = 10.60.5.4
appsAcrName                 = cr4bqvj62ztmxmi
appsAcrResourceGroupName    = rg-ops
registryHostname            = registry-github.adriangarciacruz.com
keycloakHostname            = keycloak.adriangarciacruz.com
keycloakUrl                 = http://keycloak.platform.internal:8080
keycloakExternalUrl         = https://keycloak.adriangarciacruz.com
keycloakDbHost              = psql-litellm-4bqvj62ztmxmi.postgres.database.azure.com
keycloakDbServerName        = psql-litellm-4bqvj62ztmxmi
keycloakDbResourceGroupName = rg-ai-access
```

The application VM size is `Standard_E2ds_v7`. Edge, etcd, and OpenBao use
`Standard_D2ls_v7`. The foundation VM modules are disabled because those VMs
already existed and Azure rejected attempts to alter their custom data.

Immutable image references used by the VM parameter file:

```text
Registry:
cr4bqvj62ztmxmi.azurecr.io/registry@sha256:d8649aa821308bb6df7daf9dea9e0c8c50fd4cc7066d2e02570aa248861ed5a7

Auth server:
cr4bqvj62ztmxmi.azurecr.io/auth-server@sha256:bb2334d1835afb37547793799d99478d38c22896a1f29780535f4bfa63a920c7

MCP gateway:
cr4bqvj62ztmxmi.azurecr.io/mcpgw@sha256:86df691ab2c6ff613422341245f1d8b6434792cd407a454407f36385644c6a26

Keycloak:
quay.io/keycloak/keycloak@sha256:89aae522be5c945670620f61bdabed612835fb151de8d5aa7091d093e1718a30
```

Do not replace these digest references with `latest` or another mutable tag
without an explicit release decision.

## OpenBao state and recovery history

OpenBao endpoint:

```text
https://openbao.platform.internal:8200
```

OpenBao uses:

- Private TLS signed by the platform CA.
- Raft data on the VM data disk.
- Azure Key Vault auto-unseal.
- Key Vault key: `openbao-unseal`.
- The OpenBao VM system-assigned managed identity.
- No published Raft cluster listener on port `8201`.

The platform Key Vault is:

```text
kvplatformrtsxkr2fmvx42
```

The OpenBao `secret` KV v2 mount was missing during the first restricted-token
validation and was created during recovery. It now exists.

The `registry-egress` policy is intentionally restricted to the Registry's
egress namespace:

```hcl
path "secret/data/mcp/egress/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "secret/metadata/mcp/egress/*" {
  capabilities = ["read", "list", "delete"]
}
```

The first token transfer was corrupted during manual handling and was revoked.
The later recovery path was corrected using the OpenBao source behavior:

1. Generate a 26-character base62 OTP.
2. Start the documented root-generation attempt.
3. Submit the recovery key to the update endpoint.
4. Decode the raw base64 response by XORing decoded ciphertext bytes with the
   OTP bytes.
5. Validate the resulting temporary root capability.
6. Create a new orphaned, non-renewable Registry token with only
   `registry-egress`.
7. Test raw KV v2 write/read/delete operations with that token.
8. Encrypt the token for transfer and decrypt it only in the operator workspace.
9. Store it in Key Vault as `openbao-registry-token`.
10. Revoke the temporary root token.

The final restricted token was verified against the live OpenBao KV paths before
being written to Key Vault. The application VM then synchronized it and
successfully performed a write/read/delete test against a temporary
`secret/data/mcp/egress/...` path. The temporary test record was deleted.

Do not repeat recovery unless OpenBao itself is lost. Do not put recovery keys,
root tokens, or the Registry token in this repository, Bicep, Compose files,
command-line arguments, or ordinary logs.

## Secret flow

The intended flow is:

```text
Operator-controlled seed files
  -> Azure Key Vault
  -> VM system-assigned managed identity
  -> platform-secret-sync.service
  -> protected files under /etc/platform/
  -> Compose secrets or generated dotenv files
```

The application VM reads these individually scoped Key Vault secrets:

```text
registry-secret-key
auth-server-nginx-marker-secret
mongodb-connection-string
embeddings-api-key
keycloak-client-secret
keycloak-m2m-client-secret
openbao-registry-token
platform-ca-cert
```

The Keycloak VM reads:

```text
keycloak-admin-password
keycloak-db-password
```

`openbao-registry-token` is mounted directly into the Registry container as a
file-backed Compose secret at `/run/secrets/openbao_registry_token`. It is not
rendered into the Registry dotenv file.

The OpenBao token and platform CA are synchronized to:

```text
/etc/platform/secrets/raw/openbao-registry-token
/etc/platform/tls/platform-ca.crt
```

The application identity has per-secret Key Vault role assignments, not whole
vault access. The Keycloak identity has only its two named secret scopes. The
application identity also has `AcrPull` on the existing ACR.

## Why the deployment took manual repair

Several independent issues were encountered:

### Existing VM custom data is immutable

Redeploying the Bicep modules against already-created VMs failed with:

```text
PropertyChangeNotAllowed: Changing property 'osProfile.customData' is not allowed.
```

This affected the application and Keycloak VM retries after source bootstrap
changes. The safe options are:

- Apply a narrowly scoped live repair over SSH.
- Use a separate configuration-management path.
- Deliberately recreate only the affected VM after preserving required data and
  confirming the blast radius.

Do not set `deployFoundationVms=true` while intending to reuse the existing edge,
etcd, or OpenBao VMs.

### Key Vault URI and Bicep interpolation defects

The original generated VM configuration had:

```text
https://kvplatformrtsxkr2fmvx42..vault.azure.net/
```

and literal strings such as `${registrySecretKeyName}` in the generated
secret-sync configuration. The source fixes were:

- `platform/azure/infra/modules/ops.bicep`: remove the extra dot before the
  Key Vault DNS suffix.
- VM modules: use `join([...], '\n')` rather than non-interpolating multiline
  strings for secret mappings and OpenBao environment content.

Compile the Bicep before deploying:

```bash
az bicep build \
  --file platform/azure/infra/main.bicep \
  --outfile /tmp/main.json
```

Confirm the compiled output contains neither `..vault.azure.net` nor literal
`${...}` secret placeholders.

### ACR authentication

The application VM initially failed to pull images:

```text
error from registry: authentication required
```

The managed identity was granted `AcrPull` on `cr4bqvj62ztmxmi`. Azure CLI was
installed on the VM, and the live VM now has:

```text
/usr/local/sbin/platform-acr-login
```

The script runs:

```bash
az login --identity --allow-no-subscriptions --output none
az acr login --name cr4bqvj62ztmxmi --only-show-errors
```

The application systemd unit has an `ExecStartPre` for this login. The durable
source changes are in:

```text
platform/azure/scripts/bootstrap/host-bootstrap.sh
platform/azure/scripts/bootstrap/platform-apps-files.sh
platform/azure/scripts/systemd/platform-apps.service
platform/azure/infra/modules/application-vm.bicep
```

Because custom data is immutable, the live hook was installed manually on the
existing VM. A future replacement VM will receive it from bootstrap.

### Registry shared-volume ownership

The Registry image runs as UID/GID `1000:1000`. The host-created application
directories were initially root-owned, so Nginx could not create its shared
access log. The source bootstrap now includes:

```bash
chown -R 1000:1000 /var/lib/platform/apps/registry /var/log/containers/ai-registry
```

The live ownership repair and final health check are complete.

## VM access and health checks

Use Azure Bastion native SSH for agent-operated access. The SSH key must remain
outside the repository:

```bash
VM_ID="$(az vm show \
  --resource-group rg-mcp-registry \
  --name vm-platform-apps \
  --query id \
  --output tsv)"

az network bastion ssh \
  --name bas-vnet-platform-pilot \
  --resource-group rg-network \
  --target-resource-id "$VM_ID" \
  --auth-type ssh-key \
  --username platformadmin \
  --ssh-key "$HOME/.ssh/id_ed25519"
```

Do not print dotenv files, raw secret files, Compose environment output, or
OpenBao token values while diagnosing. Azure VM Run Command is the fallback
when the Bastion SSH extension is unavailable.

Expected application containers:

```text
apps-registry-1
apps-auth-server-1
apps-mcpgw-server-1
```

Expected local health checks:

```bash
curl --fail http://10.60.4.4:8080/health
curl --fail http://127.0.0.1:8888/health
curl --fail http://127.0.0.1:8003/health
```

The auth-server, MCP gateway, and Registry checks now return HTTP 200 or a
successful health response.

## Edge, Keycloak, and remaining acceptance

The following cutover work is complete:

- APISIX routes Registry to `http://10.60.4.4:8080` and Keycloak to
  `http://10.60.5.4:8080`, with the public host headers and forwarded HTTPS
  metadata required by the applications.
- The edge VM received the newer scheme/port-aware renderer and route bootstrap
  manually because its existing VM custom data is immutable.
- The Keycloak VM runs the pinned image with `KC_HOSTNAME` set to the full
  canonical HTTPS URL. This prevents internal authorization-code exchanges from
  producing an issuer containing the private HTTP port.
- The persisted `mcp-gateway` realm was reused. Do not rerun
  `keycloak/setup/init-keycloak.sh` without reviewing its effects because it can
  regenerate client secrets.
- Private authenticated `/api/auth/me` succeeds through both the application VM
  and APISIX with the repaired M2M service-account token.
- A private full OAuth browser flow succeeds through Keycloak login, the Registry
  callback, session-cookie creation, and `/api/auth/me`.

The following acceptance work remains:

1. Test Registry persistence, MCP gateway routing, restart/recovery, and ACA
   rollback behavior before retiring rollback capacity.

Keycloak initialization is confirmed over the private Bastion path. The
application realm was already present in the shared PostgreSQL database; the
M2M service account's expected group memberships were repaired without
regenerating client secrets.

## Safe diagnostic commands

From an authenticated Azure operator workstation:

```bash
az vm show \
  --resource-group rg-mcp-registry \
  --name vm-platform-apps \
  --show-details \
  --query '{power:powerState,privateIp:privateIps,provisioning:provisioningState}' \
  --output json

az vm show \
  --resource-group rg-mcp-keycloak \
  --name vm-platform-keycloak \
  --show-details \
  --query '{power:powerState,privateIp:privateIps,provisioning:provisioningState}' \
  --output json

az keyvault secret show \
  --vault-name kvplatformrtsxkr2fmvx42 \
  --name openbao-registry-token \
  --query '{id:id,enabled:attributes.enabled}' \
  --output json
```

The last command intentionally does not request the secret value.

If SSH is temporarily unavailable, Azure VM Run Command is a fallback control
channel, not the preferred operational workflow. Use it only for narrowly
scoped, non-secret repairs and never place secret values in the command
arguments.

## Validation already completed

The Azure validation plan is `.azure/deployment-plan.md` and remains marked
`Validated`. The recorded validation included:

- Subscription and policy context review.
- Bicep validation and lint.
- What-if summary: Create 10, Deploy 28, Ignore 32, Unsupported 2, Delete 0.
- Shell syntax checks.
- Python syntax checks.
- Quota and RBAC review.
- Role verification for VM identities.

The two unsupported what-if resources were dynamic role assignments whose
principal IDs are only available during deployment. No destructive what-if
changes were reported.

The application VM ACR and Key Vault role assignments were subsequently
created and verified during runtime setup. The Registry OpenBao token is an
application-level policy credential, not an Azure RBAC role.

## Relevant source files

Start with these files:

```text
platform/azure/README.md
platform/azure/infra/main.bicep
platform/azure/infra/modules/network.bicep
platform/azure/infra/modules/ops.bicep
platform/azure/infra/modules/application-vm.bicep
platform/azure/infra/modules/keycloak-vm.bicep
platform/azure/infra/modules/openbao-vm.bicep
platform/azure/infra/modules/key-vault-secret-role.bicep
platform/azure/infra/modules/acr-pull-role.bicep
platform/azure/config/apps/compose.yaml
platform/azure/config/apps/README.md
platform/azure/config/openbao/openbao.hcl
platform/azure/config/openbao/compose.yaml
platform/azure/config/openbao/README.md
platform/azure/config/secrets/README.md
platform/azure/scripts/secret-sync/platform-secret-sync.py
platform/azure/scripts/bootstrap/host-bootstrap.sh
platform/azure/scripts/bootstrap/platform-apps-files.sh
platform/azure/scripts/bootstrap/platform-apps-render.py
platform/azure/scripts/systemd/platform-apps.service
platform/azure/scripts/systemd/platform-secret-sync.service
```

The original ACA OAuth diagnosis is documented in
`platform/azure/oauth-routing-postmortem.md`. That incident involved missing
TLS SNI, incompatible ACA `/validate` subrequest defaults, and a trailing
newline in the Nginx marker secret. The same marker-format defect was reproduced
on the VM deployment and fixed in the durable application secret renderer.

## Sensitive artifacts and cleanup

Temporary OpenBao recovery and encrypted transfer artifacts were kept under
`.scratchpad/` during this session. They include recovery scripts, encrypted
payloads, transfer certificate material, and temporary token files. After the
deployment is fully verified:

- Remove plaintext token files.
- Remove temporary decrypted recovery output.
- Remove transfer private keys and encrypted payloads if no longer required.
- Keep the OpenBao recovery key offline under the operator's approved
  procedure.
- Do not commit `.scratchpad/` artifacts.

Do not delete the OpenBao VM or its data disk as a first troubleshooting step.
The OpenBao instance is initialized, auto-unsealing, and serving the restricted
Registry credential successfully. Recreate it only after an explicit decision
that the Raft data and recovery material can be discarded or restored.

## Hybrid Worker onboarding handoff

**Updated:** 2026-09-09 22:30 UTC
**Scope:** Azure Automation extension-based Linux User Hybrid Runbook Workers
**Automation account:** `aa-platform-pilot` in `rg-ops`, `westus3`
**Worker group:** `platform-workers`
**Subscription:** `24595c03-870c-4a3e-93b3-51ec93c246bf`

### Final live state

All five private Ubuntu 24.04 VMs are registered as `HybridV2` workers and are reporting heartbeats:

| VM | Resource group | Private IP | Worker state | Extension |
|---|---|---:|---|---|
| `vm-platform-edge` | `rg-edge` | `10.60.1.4` | Registered and heartbeating | `Succeeded`, `HybridWorkerExtension`, handler `1.1` |
| `vm-platform-etcd` | `rg-etcd` | `10.60.2.4` | Registered and heartbeating | `Succeeded`, `HybridWorkerExtension`, handler `1.1` |
| `vm-platform-openbao` | `rg-openbao` | `10.60.3.4` | Registered and heartbeating | `Succeeded`, `HybridWorkerExtension`, handler `1.1` |
| `vm-platform-apps` | `rg-mcp-registry` | `10.60.4.4` | Registered and heartbeating | `Succeeded`, `HybridWorkerExtension`, handler `1.1` |
| `vm-platform-keycloak` | `rg-mcp-keycloak` | `10.60.5.4` | Registered and heartbeating | `Succeeded`, `HybridWorkerExtension`, handler `1.1` |

The Automation Hybrid Service URL used by every extension is the account's `automationHybridServiceUrl` value. It is not the legacy `RegistrationUrl`.

### Root cause of the 401

The failed onboarding attempts installed the extension before creating the corresponding `Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups/hybridRunbookWorkers` resource. Microsoft Learn's extension-based onboarding sequence requires both steps:

1. Create the Hybrid Worker group.
2. Create a worker resource in that group using a new GUID and the VM resource ID.
3. Enable the VM's system-assigned managed identity.
4. Install the extension with resource instance name `HybridWorkerExtension`, type `HybridWorkerForLinux`, and handler version `1.1`.

The earlier manually created `platform-workers` group was empty. The extension reached the Automation endpoint but registration was rejected with HTTP 401 because the VM had not been associated with a worker resource. Creating the worker resource for `vm-platform-apps` immediately changed the result from 401 to a live heartbeat. The same sequence then succeeded for the remaining four VMs.

### Important Microsoft Learn alignment

The deployed configuration intentionally matches the documented values:

- Extension resource instance name: `HybridWorkerExtension`
- Publisher: `Microsoft.Azure.Automation.HybridWorker`
- Extension type: `HybridWorkerForLinux`
- Handler version: `1.1`
- Public setting: `AutomationAccountURL` set to `automationHybridServiceUrl`
- VM identity: system-assigned managed identity enabled
- Worker resource type: `HybridV2`

The old failed extension instance named `HybridWorkerForLinux` was removed from each VM before the correctly named extension was installed.

### Test-bench Python compatibility

Ubuntu 24.04 provides Python 3.12, but handler `1.1.45` imports the removed Python `imp` module. The supported Azure extension artifact still requires a Python 3.10-compatible runtime on this test bench.

UV installed CPython `3.10.18` on every VM at:

```text
/opt/platform/uv/bin/uv
/opt/platform/python310/cpython-3.10.18-linux-x86_64-gnu/bin/python3.10
```

The compatibility installer also creates `/usr/local/bin/Python` and `/usr/local/bin/python3`. For this test bench, `/usr/bin/python3` was redirected to the UV-managed 3.10 interpreter so the extension's `#!/usr/bin/env python3` scripts can import `imp`. The original Ubuntu binary remains available as `/usr/bin/python3.12`.

This is an aggressive compatibility workaround, not a general production default. Before using these VMs for normal Ubuntu administration, test package management, cloud-init, monitoring agents, and OS maintenance. To restore the Ubuntu interpreter after worker testing, replace `/usr/bin/python3` with the approved `/usr/bin/python3.12` link or binary and keep the UV runtime only for the worker handler if a future handler supports an explicit interpreter path.

The repository installer is opt-in and lives at:

```text
platform/azure/scripts/bootstrap/install-python310-compat.sh
```

### Infrastructure changes

The following infrastructure behavior is now represented in Bicep and the generated ARM template:

- `platform/azure/infra/modules/ops.bicep` creates the worker group when `deployHybridWorkers` is enabled.
- The operations module creates one worker resource per configured VM resource ID using a deterministic GUID.
- `platform/azure/infra/modules/hybrid-worker-extension.bicep` installs the VM-scoped extension with the documented instance name and handler version.
- `platform/azure/infra/main.bicep` passes the five existing VM resource IDs into the operations module.
- `platform/azure/infra/main.json` was regenerated from the final Bicep.
- The worker feature remains opt-in through `deployHybridWorkers`; it is not enabled by default.

Do not deploy the worker modules with `deployHybridWorkers=true` until the target VM resource IDs exist. The worker registration resources intentionally reference existing VMs.

### Verification commands

Use WSL Azure CLI for this environment:

```bash
az automation hrwg hrw list \
  --resource-group rg-ops \
  --automation-account-name aa-platform-pilot \
  --hybrid-runbook-worker-group-name platform-workers \
  --output table

az vm extension show \
  --resource-group rg-mcp-registry \
  --vm-name vm-platform-apps \
  --name HybridWorkerExtension \
  --output json
```

Expected worker output includes `workerType: HybridV2`, a non-empty `lastSeenDateTime`, and the expected VM resource ID. Expected extension output includes `provisioningState: Succeeded`, `typePropertiesType: HybridWorkerForLinux`, and `typeHandlerVersion: 1.1`.

### Validation completed

- Bicep compilation succeeded with `az bicep build`.
- Shell syntax validation succeeded for the modified deployment and Python compatibility scripts.
- The focused runbook test suite passed: `43 passed`.
- The test suite was local-only. It did not publish, schedule, or execute an Azure Automation runbook, and it did not connect to MongoDB, Keycloak, Azure, or the VMs.
- All five live extensions report `Succeeded`.
- All five live workers report heartbeats in `platform-workers`.

### Remaining work

The worker fleet is operational, but the Registry schema runbook has not yet been published or scheduled. The next controlled steps are:

1. Build the source-only archive with `platform/runbooks/package.py`.
2. Upload it to an immutable, private artifact location.
3. Publish the runbook only after the artifact URI and immutable version are known.
4. Run a harmless `discover` or `registry-schema-verify` job explicitly on `platform-workers`.
5. Confirm job output and audit records.
6. Add a schedule only after one manual read-only job succeeds.

Do not treat the local `43 passed` result as proof of Azure Automation execution. It proves the runbook modules and validation logic pass their focused local tests only.

### Operational cautions

- Do not rerun Keycloak bootstrap to troubleshoot Registry authorization; the Registry scope repair was separate and already seeded.
- Do not drop MongoDB collections as a worker troubleshooting step.
- Do not put connection strings, bearer tokens, or secret values into Run Command arguments or handoff documents.
- Do not blindly retry failed extensions. First verify the worker resource exists in the Automation group, then verify the extension instance name, handler type, handler version, and Automation Hybrid Service URL.
- Keep the `/usr/bin/python3` compatibility switch documented as test-bench-only until the operating-system impact is explicitly accepted.
