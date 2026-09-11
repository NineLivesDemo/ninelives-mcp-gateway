# Terraform implementation progress

> Status updated after the 2026-09-10 Azure deployment. The deployed
> environment is now represented by `terraform/env/dev/`; older planning
> references to `terraform/live/platform-pilot/` are superseded.

Last updated: 2026-09-10

## Current architectural framing

This repository follows the Cloud Adoption Framework distinction between:

- The **platform landing zone**, which provides shared governance, connectivity,
  security, DNS, controlled egress, and shared platform capabilities.
- **Application landing zones**, which own individual business workloads and
  their environments.

The initial experimental development environment models these boundaries within
one Azure subscription using separate resource groups, VNets, Terraform
compositions, and ownership contracts. It does not require management-group
hierarchy or subscription vending yet.

Reference:

- [Azure landing zones: platform and application landing zones](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/?tabs=conceptual%2Cplatvsapp)
- [Enterprise-scale architecture PDF](../docs/enterprise-scale-architecture.pdf)

## Non-negotiable ingress invariant

All externally initiated application traffic must follow:

```text
Cloudflare Tunnel -> APISIX -> private workload upstream
```

Workload/application landing zones must not create public application
endpoints, public VM ingress, direct public DNS, or alternate paths that bypass
the tunnel and APISIX.

## Ownership boundaries

- Terraform owns Azure control-plane infrastructure and explicitly owned
  Cloudflare control-plane resources.
- Ansible owns VM-local packages, Docker/Compose, systemd, APISIX, cloudflared,
  etcd, OpenBao, Keycloak runtime, application runtime, certificates, and
  health checks.
- Existing Azure Key Vault remains the Azure-native secret source where
  required. The secret-management boundary is Vault-compatible: Managed Vault
  is the active backend for Terraform bootstrap and runtime operations for now,
  while self-hosted OpenBao is the deferred implementation option.
- Secret values must not enter Terraform variables, outputs, ordinary state,
  cloud-init, or unmanaged files.
- Managed Vault is the active Vault-compatible backend because the current
  AppRole and KV workflow is working reliably. Key Vault remains for
  Azure-native use cases where it remains the correct boundary. OpenBao is the
  deferred self-hosted implementation of the same secret-management role.
- The recently created replacement PostgreSQL server is Terraform-owned within
  the experimental platform boundary; any database that has existed for months
  is protected and must not be modified or deleted.
- Existing ACA/ACAE resources and all AI resources are protected and must not be
  modified or deleted.
- ACR is an existing shared dependency and is referenced, not recreated.
- MongoDB Atlas and Grafana Cloud remain external dependencies.

## Ansible execution decision

### Adopted HashiCorp Pattern 1

Decision recorded 2026-09-10: adopt HashiCorp's primary
"Provision with Terraform, configure with Ansible" integration pattern.
Semaphore UI is the leading workflow controller and Ansible execution layer.
It orchestrates the workflow but does not replace Terraform as the
infrastructure authority.

The adopted flow is:

```text
Semaphore/Ansible workflow
  -> HCP Terraform workspace plan/apply
  -> deliberately shaped Terraform outputs
  -> output-based Ansible dynamic inventory
  -> Ansible configuration roles
  -> service and platform health validation
```

Terraform remains responsible for Azure infrastructure lifecycle and state.
Ansible remains responsible for VM-local and runtime configuration. The
Ansible execution environment must have private reachability to the VMs,
private DNS, and the active Vault-compatible secret backend; HCP Terraform
workers do not need SSH access to the private workload subnets.

Rationale:

- The workflow controller can sequence infrastructure provisioning and host
  convergence without moving infrastructure ownership into Ansible.
- HCP Terraform remains the source of truth for infrastructure state.
- Deliberately shaped outputs provide a controlled, non-sensitive contract
  instead of exposing raw Terraform state.
- The Ansible runner, rather than the HCP Terraform worker, handles private
  SSH and runtime configuration.
- The same Ansible project remains portable to `ansible-core`,
  `ansible-runner`, and a future execution controller.

Supporting mechanisms:

- Use output-based dynamic inventory and the Terraform API, not direct state
  backend access.
- Use a pinned execution environment containing `ansible-core`, required
  collections, `pytfe`, and required Python libraries.
- Reserve Terraform Actions for bounded, approved day-two operations.
- Defer event-driven post-apply automation until the manual workflow is
  proven reliable.

The following are not part of the baseline:

- Terraform directly launching the complete Ansible platform through
  `ansible_playbook_run` or an equivalent provider resource.
- Terraform Actions as a generic Ansible runner.
- AAP-specific integration.

Keep the Ansible project portable so it can run through Semaphore UI,
`ansible-core`, or `ansible-runner` without changing the Terraform contract.
Use Molecule for role and playbook testing, including delegated integration
against the durable Azure topology where appropriate. Do not add the AAP
Terraform provider or couple Terraform apply to AAP job execution.

## Implemented locally

- Terraform binary available: Terraform 1.16.1.
- AVM ALZ connectivity pattern downloaded and pinned:
  `Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm` version `0.17.5`.
- Transitive AVM modules and providers downloaded by `terraform init`.
- Provider selections recorded in `terraform/env/dev/.terraform.lock.hcl`.
- Thin root created at `terraform/env/dev/`.
- Repository-owned connectivity composition created at
  `terraform/modules/connectivity/`.
- Connectivity composition currently exposes typed inputs for:
  - hub resource group
  - hub VNet name and CIDRs
  - hub subnets
  - tags
  - Bastion, NAT, Firewall, and shared Private DNS capability gates
- Connectivity outputs currently expose hub VNet, Bastion, and NAT IDs.
- The AVM pattern is used for shared hub capabilities only. Ingress/platform
  and application landing-zone VNets will use the AVM VNet resource module with
  explicit peerings and independent ownership.
- Platform composition now creates the private ingress/platform-services VNet
  with the AVM VNet resource module and configures bidirectional hub peering
  using the module's `peerings` interface and reverse-peering support.
- Initial application landing-zone composition added with a private workload
  VNet, private subnet inputs only, and explicit bidirectional hub peering.
  The composition has no public endpoint, public IP, or public-ingress input.
- Added an AVM private DNS zone composition for PostgreSQL private-link name
  resolution, linked to the hub, ingress/platform-services, and application
  landing-zone VNets. It creates no public DNS records or endpoints.
- Added an AVM managed-identity composition for platform operations,
  application runtime, and Keycloak runtime identities. Role assignments now
  require explicit scope maps; the current environment supplies none until the
  Key Vault, existing ACR, VM, and secret-consumer boundaries are finalized.
- Added a Terraform-owned AVM PostgreSQL Flexible Server composition using an
  ephemeral administrator password and the provider's write-only password
  argument. Public network access is disabled, and the server uses a dedicated
  private-endpoint subnet plus the PostgreSQL private DNS zone.
- Added private VM foundations for edge, etcd, OpenBao, application, and
  Keycloak using AVM `avm-res-compute-virtualmachine` `0.21.0`. They have no
  public IPs, use Bastion-mediated SSH with an operator-supplied public key,
  and receive only their role-appropriate managed identity. APISIX,
  cloudflared, etcd, OpenBao, Keycloak, certificates, and application runtime
  configuration remain Ansible-owned.
- Added the dedicated private automation VM and automation subnet for
  Semaphore UI. The subnet has a scoped Standard NAT gateway for outbound
  package and image retrieval; the VM has no public IP and Semaphore ingress
  remains limited to Bastion.
- Bootstrapped Semaphore `v2.19.12` with PostgreSQL `14.3` and a registered
  runner on the automation VM. Deployment credentials are stored outside the
  repository with restrictive permissions and are not represented in
  Terraform.
- Added explicit private VM subnet network policy with per-subnet NSGs and
  route tables. The policy permits only Bastion SSH and the documented
  east-west service flows (edge to etcd/application/Keycloak and application
  consumers to OpenBao), then denies all other inbound traffic. Route tables
  currently have no custom routes, preserving Azure system routing until a
  controlled firewall next hop is introduced.
- Added non-secret environment outputs for subnet IDs, VM resource IDs,
  network interface IDs, and PostgreSQL server metadata for Ansible handoff.
- Added opt-in, resource-ID-driven RBAC wiring. Key Vault access is scoped to
  the documented individual secret resources, ACR access is limited to
  `AcrPull` on the existing registry, and OpenBao auto-unseal access is scoped
  to the existing key. No role assignments are created while those existing
  resource IDs remain unset.
- Added `scripts/validate-terraform-private-ingress.sh`, a static guard that
  checks the tunnel/APISIX/private-upstream contract and rejects public IP
  settings in private VM and application landing-zone modules.
- Disabled the AVM connectivity pattern's default DDoS Protection Plan for the
  experimental topology and disabled PostgreSQL firewall rules explicitly. Bastion
  remains the only intentionally public management endpoint; workload VMs and
  PostgreSQL remain private.
- Isolated the replacement environment into four new lifecycle-scoped resource
  groups: network, services, app, and data. Existing legacy resource groups
  remain outside Terraform ownership for this replacement.
- `terraform fmt` and `terraform validate` pass.
- Private ingress static validation passes.
- Terraform has refreshed Azure state and successfully deployed the replacement
  environment. State is currently local at `terraform/env/dev/terraform.tfstate`;
  a remote backend remains future work.

## Next implementation sequence

1. Inspect the Ansible tree and map the five deployed VMs to roles.
2. Generate a non-secret Ansible inventory from Terraform outputs.
3. Bootstrap the common OS baseline, then etcd, OpenBao, Keycloak,
   application services, APISIX, and cloudflared in dependency order.
4. Reconcile existing resource IDs and enable only the required opt-in RBAC
   inputs.
5. Add Cloudflare and Keycloak provider integrations only after their ownership
   and bootstrap sequencing are explicit.
6. Run static and runtime verification for the
   Cloudflare Tunnel -> APISIX -> private upstream invariant.

Boundary is deferred for now. Use Azure Bastion for private VM management while
the runtime platform and Ansible workflow are being established. Revisit Boundary
after the services are healthy and the access requirements are clearer.

## Known items to reconcile before further Azure changes

- Decide the remote state backend and state isolation; the current state remains
  local for this experimental topology.
- Confirm whether any retained legacy VNets are still needed by external
  dependencies before changing or removing them.
- Keep the deployed resource-group split and replacement PostgreSQL name
  (`psql-platform-dev-2`) consistent across follow-up tooling.
