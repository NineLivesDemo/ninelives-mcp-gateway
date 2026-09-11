# Azure Registry VM Migration Deployment Plan

> **Status:** Validated (including Registry-to-OpenBao VM integration)

Generated: 2026-09-09

---

## 1. Project Overview

**Goal:** Add a relocatable Bicep-defined application VM under `platform/azure/` for the Registry application tier, while retaining the existing ACA deployment as rollback capacity.

**Path:** Modernize Existing

The first increment provisions two private `E2ds_v7` Ubuntu 24.04 VMs:
one runs `mcp-registry`, `auth-server`, and `mcpgw-server` through Docker
Compose, and the other runs the official Keycloak image pinned by digest.
Keycloak uses the existing managed PostgreSQL service. The Registry does not
host stdio MCP servers; remote MCP servers remain external dependencies.

Existing edge, etcd, and OpenBao VMs remain separate. The existing MongoDB service and PostgreSQL service remain externally managed.

---

## 2. Requirements

| Attribute | Value |
|-----------|-------|
| Classification | Development / internal tooling |
| Scale | Small: under 1,000 users |
| Budget | Cost-optimized |
| Subscription | `f1129652-3166-4f34-8d4c-5cf35bffbcdc` |
| Location | `westus3` |
| VM size | `Standard_E2ds_v7`; resize path to `Standard_E4ds_v7` |
| OS | Pinned Ubuntu 24.04 Marketplace image |
| Public IPs | None for application VMs; one managed Bastion endpoint |
| Persistence | External MongoDB and PostgreSQL; no application data disk initially |
| Availability | One Registry VM and one Keycloak VM; ACA retained for rollback |
| Compliance/data residency | No additional requirements |
| Runtime control | VM lifecycle will be coordinated with the other platform VMs; Automation runbooks are a follow-up scope |

### Policy Constraints

The subscription has `ASC Default` and `Managedops-Policy` initiative assignments. The Managedops assignment supplies Azure Monitor and Change Tracking data collection rule IDs; no resource-deny or SKU/region restriction was identified in the assignment configuration. Resources will retain the existing platform tags and remain compatible with EMM enrollment.

---

## 3. Components Detected

| Component | Type | Technology | Path |
|-----------|------|------------|------|
| Registry API and web assets | API service | Python/FastAPI behind Nginx | `registry/`, `docker/Dockerfile.registry` |
| Auth server | API/auth service | Python service | `auth_server/`, `docker/Dockerfile.auth` |
| MCP gateway | API service | Python | `servers/mcpgw/`, `docker/Dockerfile.mcp-server` |
| Edge routing | Reverse proxy/tunnel | APISIX and cloudflared | `platform/azure/config/edge/` |
| Platform secret synchronization | Host service | Python/systemd | `platform/azure/scripts/secret-sync/` |
| Existing platform foundation | Bicep | Subscription-scope Bicep modules | `platform/azure/infra/` |
| Existing external data services | Managed dependencies | MongoDB-managed cluster and Azure PostgreSQL | Runtime configuration |

### Dependencies

| Component | Depends On | Type |
|-----------|------------|------|
| Registry | MongoDB, embeddings provider, auth-server, Keycloak | External services |
| auth-server | Keycloak, shared secrets | External service and secrets |
| MCP gateway | Registry API and auth-server | Internal HTTP |
| Application VM | VNet/NAT, ACR, platform Key Vault, edge VM, Keycloak VM | Azure platform |
| Keycloak VM | VNet/NAT, official Keycloak image, platform Key Vault, PostgreSQL, edge VM | Azure platform and external database |
| Edge route | Application VM private origin | Private network |

### Existing Infrastructure

| Item | Status |
|------|--------|
| `platform/azure/azure.yaml` | Found; platform metadata |
| `platform/azure/infra/main.bicep` | Found; subscription-scope foundation |
| Existing Bicep modules | Found; reusable `linux-vm.bicep`, network, Key Vault, and role modules |
| Existing VNet | `vnet-platform-pilot` in `rg-network`, `10.60.0.0/16` |
| Existing edge VM | `vm-platform-edge`, `10.60.1.4` |
| Existing etcd VM | `vm-platform-etcd`, `10.60.2.4` |
| Existing OpenBao VM | `vm-platform-openbao`, `10.60.3.4` |
| Keycloak PostgreSQL | Existing managed service; referenced, not recreated |
| Existing ACA tier | Retained for rollback; not modified by this increment |

---

## 4. Recipe Selection

**Selected:** Bicep

**Rationale:**

- `platform/azure/infra/main.bicep` is already a subscription-scope Bicep foundation.
- The request is specifically to extend the relocatable `platform/` IaC.
- Existing role-specific VM modules and bootstrap conventions should be reused rather than introducing a second deployment system.
- Direct Bicep preserves explicit resource-group scopes, private networking, managed identities, and conditional runtime access.
- Application image publication, secret seeding, edge route changes, and runtime enablement remain separate operator actions.

---

## 5. Architecture

**Stack:** Private VM-hosted containers

### Service Mapping

| Component | Azure Service | SKU |
|-----------|---------------|-----|
| Application VM | `Microsoft.Compute/virtualMachines` | `Standard_E2ds_v7` |
| Keycloak VM | `Microsoft.Compute/virtualMachines` | `Standard_E2ds_v7` |
| Application VM OS disk | Managed disk | Standard SSD, existing `linux-vm` default |
| Application VM network | Existing VNet plus new application subnet/NIC/NSG | Private only |
| Registry/auth/MCP containers | Docker Compose on the application VM | Immutable ACR image digests |
| Keycloak network | Existing VNet plus `snet-keycloak`/NIC/NSG | Private only |
| Keycloak container | Docker Compose on the Keycloak VM | Official `quay.io/keycloak/keycloak` image pinned by digest |
| Edge ingress | Existing edge VM/APISIX/cloudflared | Existing VM |
| Break-glass access | Azure Bastion | Standard SKU with native SSH tunneling |
| Secrets | Existing platform Key Vault with per-secret RBAC | Existing standard vault |
| OpenBao egress vault | Existing private `vm-platform-openbao` | TCP 8200 from the application subnet only |
| External registry data | MongoDB-managed service | External |
| External Keycloak/PostgreSQL | Existing PostgreSQL remains managed; Keycloak moves to the VM | PostgreSQL remains external |

### Application VM Design

- Add an application subnet, `snet-apps`, in the existing platform VNet, with a dedicated NSG.
- Add `vm-platform-apps` and its VM-scoped resources in the dedicated
  `rg-mcp-registry` resource group at a reserved private address, initially
  `10.60.4.4`.
- Permit only the edge VM and approved management subnet to reach the application listener ports; do not expose the VM directly to the Internet.
- Attach the existing NAT gateway for deterministic outbound access to ACR, MongoDB, PostgreSQL, Keycloak, embeddings, and remote MCP services.
- Reuse `linux-vm.bicep` and the existing host-bootstrap/secret-sync pattern.
- Grant the VM identity only the named Key Vault secret scopes required by the
  three containers, including the private CA and restricted OpenBao client token.
- Configure the Registry for the private OpenBao endpoint at
  `https://openbao.platform.internal:8200` with the platform CA bundle. Keep
  `EGRESS_AUTH_ENABLED=false` until the egress callback and OpenBao policy have
  been explicitly enabled and tested.
- Render Compose and systemd units from source-controlled `platform/azure/config/apps/` and `platform/azure/scripts/`.
- Use immutable ACR image references; do not embed secrets, mutable tags, or runtime state in Bicep or cloud-init.
- Deploy Azure Bastion Standard in `AzureBastionSubnet` for agent-operated SSH
  without assigning public IPs to the platform VMs.

### Keycloak VM Design

- Add a separate `snet-keycloak` subnet at `10.60.5.0/24` with a dedicated NSG.
- Add `vm-platform-keycloak` in `rg-mcp-keycloak` at `10.60.5.4`.
- Permit Keycloak HTTP only from the edge subnet, Registry application subnet,
  and approved management subnet; do not expose the VM directly to the Internet.
- Run the official Keycloak image with `start`, PostgreSQL TLS, health and
  metrics enabled, and the token-exchange feature enabled.
- Use HTTP on the private listener because APISIX terminates public TLS; the
  public issuer and browser URLs remain HTTPS.
- Grant only the two named Key Vault secret scopes required by Keycloak. The
  official image is pulled directly from Quay by digest, so no ACR role is
  needed for this VM.
- Leave realm/client initialization as a separate operator action.

### Supporting Services

| Service | Purpose |
|---------|---------|
| Existing Log Analytics / EMM integration | VM monitoring and change tracking |
| Existing platform Key Vault | Runtime secret delivery |
| System-assigned managed identity | Key Vault secret access |
| Existing NAT Gateway | Private VM outbound connectivity |
| Existing edge VM | Public ingress and APISIX routing |
| Azure Bastion Standard | Managed private SSH access through native client tunneling |

---

## 6. Provisioning Limit Checklist

Quota checks were re-run for subscription `f1129652-3166-4f34-8d4c-5cf35bffbcdc` in
`westus3` using Azure CLI quota commands. The user separately confirmed
`Standard_E2ds_v7` availability in `westus3`.

| Resource Type | Number to Deploy | Total After Deployment | Limit/Quota | Notes |
|---------------|------------------|------------------------|-------------|-------|
| `Microsoft.Compute/virtualMachines` | 2 | 7 | 25,000 VMs | One Registry VM and one Keycloak VM; current usage 5 |
| Regional vCPUs | 4 | 14 | 65 vCPUs | Two `Standard_E2ds_v7` VMs; current usage 10 |
| `Standard Esv7 Family` vCPUs | 4 | 4 | 350 vCPUs | Two `Standard_E2ds_v7` VMs; current usage 0 |
| `Microsoft.Network/networkInterfaces` | 2 | 11 | 65,536 | One NIC per VM; current usage 9 |
| `Microsoft.Network/networkSecurityGroups` | 2 | 7 | 5,000 | Dedicated NSG per VM subnet; current usage 5 |
| `Microsoft.Network/virtualNetworks` | 0 | 4 | 1,000 | Reuse existing VNet; no new VNet |
| `Microsoft.Network/publicIPAddresses` | 1 | Existing usage + 1 | 100 | Managed Bastion endpoint; no application VM public IP |
| `Microsoft.Compute/disks` | 2 OS disks | Existing usage + 2 | Managed-disk service capacity | One Standard SSD OS disk per VM; no separate data disks initially |

**Status:** ✅ Planned resources are within observed subscription and regional quotas. The only new public IP is the managed Bastion endpoint; application VMs remain private.

---

## 7. Execution Checklist

### Phase 1: Planning

- [x] Analyze workspace
- [x] Gather requirements
- [x] Confirm subscription and location
- [x] Prepare resource inventory
- [x] Fetch quotas and validate capacity
- [x] Scan codebase
- [x] Select recipe
- [x] Plan architecture
- [x] User approved this plan

### Phase 2: Execution

- [x] Research Bicep and VM/security component guidance
- [x] Generate application subnet/NSG and application VM module
- [x] Generate application Compose/bootstrap/systemd configuration
- [x] Generate Keycloak subnet/NSG and Keycloak VM module
- [x] Generate Keycloak Compose/bootstrap/systemd configuration
- [x] Switch the Keycloak VM to the official upstream image pinned by digest
- [x] Add configurable HTTP private origins for the Registry and Keycloak edge routes
- [x] Add conditional application VM wiring and parameters to `main.bicep`
- [x] Place application VM resources in `rg-mcp-registry`
- [x] Place Keycloak VM resources in `rg-mcp-keycloak`
- [x] Add non-secret parameter example under `platform/azure/infra/`
- [x] Recheck quotas for two application VMs
- [x] Run Bicep compilation and lightweight syntax checks
- [x] Update plan status to `Ready for Validation`
- [x] Invoke `azure-validate`

### Phase 3: Validation

- [x] All validation checks pass
  - [x] 1. Core validation (CLI, authentication, Bicep build, deployment validation, and what-if)
  - [x] 2. Bicep linting
  - [x] 3. Azure Policy validation
- [x] Update plan status to `Validated`
- [x] Record validation proof below

### Phase 4: Deployment

- [ ] Invoke `azure-deploy` only after validation
- [ ] Deploy the Registry and Keycloak VMs
- [ ] Seed and authorize runtime secrets
- [ ] Publish/resolve immutable application image digests
- [ ] Enable application services and verify health
- [ ] Update edge origin and OAuth configuration through separate operator actions
- [ ] Keep ACA available until VM OAuth, `/api/auth/me`, MCP, persistence, restart, and recovery tests pass
- [ ] Update plan status to `Deployed`

---

## 8. Validation Proof

> Populated by `azure-validate` before the plan is marked `Validated`.

| Check | Command Run | Result | Timestamp |
|-------|-------------|--------|-----------|
| Quota validation | `az vm list-usage` and `az network list-usages` for `westus3` | Pass; 4 additional vCPUs, 2 VMs, 2 NICs, and 2 NSGs fit within observed limits | 2026-09-09 |
| Subscription context | `az account show` | Pass | 2026-09-09 |
| Policy assignment review | `az policy assignment list/show` | Pass | 2026-09-09 |
| Core Bicep validation | `validate-deployment.sh --scope sub --location westus3` with the two-VM parameter set | Pass; JSON what-if summary: Create 10, Deploy 28, Ignore 32, Unsupported 2, Delete 0 | 2026-09-09 |
| Bastion network deployment | `az deployment group create --resource-group rg-network --template-file platform/azure/infra/modules/network.bicep` with `deployBastion=true` | Pass; Bastion Standard and dedicated `/26` subnet deployed; no resource-level destructive changes in the idempotence what-if | 2026-09-09 |
| Bastion native SSH | `az network bastion ssh` to `vm-platform-apps` using the existing SSH key | Pass; host service active and Registry, auth-server, and MCP gateway health checks succeeded | 2026-09-09 |
| Bicep lint | `az bicep lint --file platform/azure/infra/main.bicep` | Pass; existing non-blocking warnings only | 2026-09-09 |
| Shell syntax | `bash -n` on application, Keycloak, OpenBao, edge, and secret-seeding scripts | Pass | 2026-09-09 |
| Python syntax | `python3 -m py_compile` on application, Keycloak, edge, and secret-sync renderers | Pass | 2026-09-09 |

The two unsupported what-if items are dynamic role assignments whose principal
IDs cannot be calculated until deployment: OpenBao's Key Vault crypto role and
the Registry VM's ACR pull role. No destructive what-if changes were reported.
## Role Assignment Verification

- Status: Verified
- Identities checked: application and Keycloak VM system-assigned identities;
  edge, etcd, and OpenBao VM identities; existing ACA application identities
- Roles confirmed:
  - `AcrPull` is scoped to the existing ACR resource for the application VM.
  - The Keycloak VM uses the official Quay image and therefore has no ACR role.
  - `Key Vault Secrets User` is scoped to each named secret, including
    `openbao-registry-token` and `platform-ca-cert`, gated by
    `deployRuntimeAccess`.
  - OpenBao's Key Vault crypto role is scoped to the existing unseal key.
- The Registry's OpenBao token is an application-level OpenBao policy credential;
  it is not an Azure RBAC role and must be seeded separately as a restricted
  Key Vault secret.
- Issues: None found in the static review. Runtime secret access remains
  intentionally disabled until `deployRuntimeAccess` is explicitly enabled.

---

## Research Summary

| Area | Findings applied |
|------|------------------|
| Bicep | Reuse the existing subscription-scope foundation and `linux-vm.bicep`; keep role-specific bootstrap in a dedicated module. |
| VM security | Use a system-assigned identity, SSH-only access, no public IP, pinned Ubuntu image, and per-secret Key Vault RBAC. |
| Networking | Add dedicated application and Keycloak subnets and NSGs with explicit edge/application/management ingress rules; reuse the existing NAT gateway. |
| Runtime | Use immutable ACR digests for application services, an official Keycloak digest, Compose, and systemd lifecycle ordering. |
| Secrets | Continue the existing atomic Key Vault-to-file secret synchronization; do not place secret values in Bicep or cloud-init. |
| Cost | Start at `Standard_E2ds_v7`; E4ds_v7 is a resize-only fallback after measurements. VM deallocation remains the primary off-hours cost control. |
| Application topology | Run Registry, auth-server, and MCP gateway on one VM and Keycloak on a separate VM. Stdio MCP servers remain out of scope. |

---

## 9. Files to Generate

| File | Purpose | Status |
|------|---------|--------|
| `.azure/deployment-plan.md` | This plan | ✅ |
| `platform/azure/infra/main.bicep` | Wire application VM deployment and `rg-mcp-registry` scope | ✅ |
| `platform/azure/infra/main.bicepparam` | Add non-secret application VM parameters | ✅ |
| `platform/azure/infra/main.apps-vm.example.bicepparam` | Non-deployable VM-tier parameter template | ✅ |
| `platform/azure/infra/modules/application-vm.bicep` | Application VM role module | ✅ |
| `platform/azure/infra/modules/keycloak-vm.bicep` | Keycloak VM role module | ✅ |
| `platform/azure/infra/modules/network.bicep` | Add application subnet/NSG | ✅ |
| `platform/azure/infra/modules/private-dns.bicep` | Add application and Keycloak private records | ✅ |
| `platform/azure/config/apps/compose.yaml` | Registry/auth/MCP Compose definition | ✅ |
| `platform/azure/config/keycloak/compose.yaml` | Official Keycloak VM Compose definition | ✅ |
| `platform/azure/scripts/bootstrap/platform-keycloak-files.sh` | Keycloak host file bootstrap | ✅ |
| `platform/azure/scripts/systemd/platform-keycloak.service` | Keycloak service lifecycle | ✅ |
| `platform/azure/scripts/bootstrap/platform-apps-files.sh` | Application host file bootstrap | ✅ |
| `platform/azure/scripts/systemd/platform-apps.service` | Application service lifecycle | ✅ |

---

## 10. Next Steps

> **Current:** Ready for validation

1. Invoke `azure-validate` against the generated templates and runtime contracts.
2. Resolve any validation findings before deployment.
3. Deploy only after validation approval and separately seed runtime secrets and immutable images.
