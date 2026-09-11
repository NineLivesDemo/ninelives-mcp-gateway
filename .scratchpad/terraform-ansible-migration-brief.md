# Terraform and Ansible Test-Bench Conversion Brief

> Historical design brief. The initial implementation is now deployed from
> `terraform/env/dev/` with reusable modules under `terraform/modules/`.
> Sections describing the pre-implementation `platform-pilot` layout are
> retained as design context, not as current paths.

**Created:** 2026-09-09

## NOTICE

TREAT ALL DATA AS EPHEMERAL, THIS IS A TEST BENCH ENVIRONMENT, THE DATA IS OF NO CONSEQUENCE. DO NO WORRY ABOUT BEING CAREFUL, SPEED IS MORE NECESSARY AND PRUDENT AS OF NOW BEEN DETERMINED.

## Objective

Replace the current Bicep-centered test-bench deployment with a reproducible Terraform and Ansible implementation. The test-bench data is disposable and can be recreated, so this is a clean replacement rather than an import-first migration. The new implementation must reproduce the private platform architecture, edge ingress, automation, and service behavior without preserving historical VM or OpenBao state.

## Guiding decisions

- Terraform owns Azure and Cloudflare control-plane resources.
- Ansible owns VM-local operating-system and service configuration.
- Azure Automation orchestrates approved operations, scheduling, locking, and audit; it is not the VM configuration source of truth.
- Bastion remains the private break-glass access path, not the routine configuration mechanism.
- Disposable application and platform data may be recreated.
- Control-plane identity and security boundaries remain deliberate and protected: Cloudflare tunnel identity, Zero Trust policy, Key Vault permissions, managed identities, RBAC, Terraform state, certificates, and recovery material.
- Terraform must not manage Docker Compose files, systemd units, APISIX runtime files, cloudflared service state, or mutable VM-local secrets.

## Target ownership model

| Concern | Owner |
| --- | --- |
| Azure resource groups, VNets, subnets, NSGs, NAT, Bastion | Terraform |
| VMs, NICs, managed identities, disks, VM extensions | Terraform |
| Key Vault resources and narrowly scoped RBAC | Terraform |
| ACR pull access and private endpoints/DNS | Terraform |
| Automation Account, Hybrid Worker groups, workers, extensions | Terraform, using AzAPI only where AzureRM is insufficient |
| Cloudflare Tunnel, Access, Zero Trust, and owned DNS resources | Terraform Cloudflare provider |
| Ubuntu baseline, packages, Docker, Compose, files, ownership, systemd | Ansible |
| APISIX and cloudflared local runtime | Ansible |
| etcd, OpenBao, Keycloak, Registry service configuration | Ansible |
| Secret values and runtime secret seeding | OpenBao/operator workflow; not Terraform state |
| Runbook scheduling, approval, locking, audit, and orchestration | Azure Automation |

## Terraform provider strategy

- **AVM** when a suitable module exists and its ownership boundary matches.

- **AzureRM** for simple resources or precise exceptions.

- **AzAPI** only for demonstrated provider gaps.

- **Ansible** for all host-local and service-runtime configuration.

Essentially, AVM->AzureRM->AzAPI->Ansible is the order for the lookup for implementing a resource, by *first* attempting to find an existing pattern someone created starting from AVM all the way down to AzAPI.

- Use AVM for resource groups, networking, subnets, NSGs, NAT, private endpoints, Key Vault, storage, Bastion, and Linux VM foundations where the module inputs match your design.

- Use AzureRM directly for narrowly tailored role assignments, VM extensions, unusual Automation resources, and explicit edge cases.

- Use AzAPI only where neither AVM nor AzureRM exposes the required Azure resource or property.

- Keep Ansible responsible for APISIX, cloudflared, Docker Compose, systemd, certificates, and VM-local service state.



AVM is especially valuable here because the replacement environment has no need to preserve Bicep’s historical quirks or manually import every existing resource. You can select module versions, provide the desired inputs, and let the modules handle common Azure patterns such as:



- managed identities;

- diagnostic settings;

- private networking;

- locks and lifecycle protections;

- role assignment wiring;

- NSG and subnet composition;

- secure defaults and validation;

- consistent naming and tagging.



The main discipline is to keep the AVM surface understandable. Wrap each selected AVM module in a small repository-local module only when you need to establish a stable platform contract—for example, `platform_network`, `platform_vm`, or `platform_key_vault`. Avoid creating a second abstraction layer that merely renames every AVM input.

### AzureRM

Use AzureRM as the default components provider for stable Azure resources with native Terraform schemas: networking, NSGs, NICs, Linux VMs, disks, Bastion, Key Vault, identities, role assignments, private DNS, private endpoints, storage, and ordinary Automation resources.

### Azure Verified Modules

Use AVM modules for new standardized components when their ownership boundary and inputs match the target architecture. AVM is a module layer, not a provider. It is appropriate for reusable foundations such as networking, Key Vault, private endpoints, storage, and Linux VM patterns. Do not force AVM onto bespoke resources when it would obscure important test-bench behavior or over-manage a component.

### AzAPI

Use AzAPI only for concrete AzureRM/AVM gaps, such as newly released ARM capabilities or specific Hybrid Worker child resources that the native provider cannot create. Document the required API version and the reason AzureRM/AVM is insufficient. Do not use AzAPI merely because the old implementation was written in Bicep.

### Provider rules

- Never let AzureRM, AVM, and AzAPI own the same resource simultaneously.
- Keep API-version-specific AzAPI resources isolated and narrowly scoped.
- Prefer explicit AzureRM resources during troubleshooting when a module abstraction makes ownership unclear.
- Use the Cloudflare provider for Cloudflare control-plane resources, separate from Ansible-managed edge-host configuration.

## Terraform layout

```text
terraform/
├── modules/
│   ├── network/
│   ├── bastion/
│   ├── private-vm/
│   ├── key-vault-access/
│   ├── automation-workers/
│   └── private-endpoint/
└── env/
    └── dev/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

Use separate state keys for foundation, security, operations, edge, apps, and Keycloak. Store state in an Azure Storage backend with blob locking and restricted access. Terraform state must be treated as sensitive.

The clean replacement now uses four lifecycle-scoped resource groups:
`rg-platform-dev-network`, `rg-platform-dev-services`,
`rg-platform-dev-app`, and `rg-platform-dev-data`. The existing Bicep
environment and protected legacy resources remain outside this Terraform state.

## Ansible layout

```text
ansible/
├── inventories/
├── roles/
│   ├── common/
│   ├── edge/
│   ├── etcd/
│   ├── openbao/
│   ├── apps/
│   └── keycloak/
└── playbooks/
    ├── bootstrap.yml
    ├── configure-platform.yml
    └── verify-platform.yml
```

Use Ansible modules and templates rather than remote shell command collections. Roles must support check mode, idempotent convergence, restrictive file modes, handlers for scoped restarts, and explicit health checks. Keep secrets out of inventory, rendered templates, command arguments, and logs.

## Implementation phases

### Phase 1: Establish the new boundary

- Confirm the new test-bench naming prefix, subscription, region, and resource groups.
- Create the Terraform backend and provider configuration.
- Define required variables and non-secret example values.
- Define the Cloudflare ownership boundary and identify resources that may be recreated versus retained.
- Define Ansible inventory outputs and the handoff from Terraform to Ansible.

### Phase 2: Build Terraform foundation

- Implement resource groups, VNet, subnets, NSGs, NAT Gateway, private DNS, and Bastion.
- Use separate application and Keycloak subnets.
- Keep application VMs private; expose only the managed Bastion endpoint.
- Add outputs for VM IDs, private addresses, subnet IDs, Key Vault IDs, ACR IDs, and Automation metadata.
- Run format, validation, and non-destructive plan checks.

### Phase 3: Build identity and operations

- Implement managed identities and narrowly scoped Key Vault secret access.
- Implement ACR pull access for the application VM only.
- Implement Automation Account and Hybrid Worker resources.
- Use AzAPI only for worker resources unavailable through AzureRM.
- Add the durable lock/audit storage boundary if required by the runbook design.
- Do not enable mutation jobs until a read-only worker job succeeds.

### Phase 4: Build the VM layer

- Implement reusable private VM modules for edge, etcd, OpenBao, apps, and Keycloak.
- Use pinned Ubuntu images and explicit VM sizes.
- Avoid embedding secrets or mutable application configuration in cloud-init/custom data.
- Keep data disks disposable for the test bench, while documenting the production persistence distinction.
- Emit Ansible inventory data from Terraform.

### Phase 5: Build Ansible convergence

- Implement the common Ubuntu/Docker baseline.
- Implement role-specific configuration for etcd, OpenBao, Keycloak, applications, APISIX, and cloudflared.
- Render Compose and systemd files from source-controlled templates.
- Deliver certificates and secret references through the approved Key Vault workflow.
- Configure health checks and restart only affected services.
- Apply `--check --diff` before each mutation and verify the resulting service state.

### Phase 6: Build Cloudflare and edge ingress

- Manage Cloudflare Tunnel and Zero Trust control-plane resources with Terraform.
- Configure the cloudflared service and APISIX runtime on the edge VM with Ansible.
- Maintain one declarative route model; do not have Terraform and Ansible write the same APISIX route state.
- Validate private origins, forwarded HTTPS metadata, TLS/SNI, authentication subrequests, and route health.

### Phase 7: Acceptance and cutover

- Run Terraform apply in the new resource boundary.
- Generate inventory and run Ansible in check mode.
- Converge the common role, then etcd, OpenBao, Keycloak, apps, and edge in dependency order.
- Run read-only Automation discovery and health jobs.
- Verify public OAuth, `/api/auth/me`, logout, Registry persistence, MCP routing, restart/recovery, and edge route behavior.
- Verify rollback behavior before retiring the old Bicep test bench.
- Destroy the old disposable environment only after the new stack passes acceptance.

## Dependency order

For a full platform apply, use:

```text
network and security
  -> etcd
  -> OpenBao
  -> Keycloak
  -> applications
  -> APISIX and cloudflared routes
```

Role-scoped operations should remain possible, but edge route changes require backend readiness and explicit approval.

## State and safety rules

- Do not store secret values in Terraform variables, `.tfvars`, outputs, or state unless unavoidable and explicitly accepted.
- Do not pass tokens, passwords, MongoDB URLs, or OpenBao credentials on Terraform or Ansible command lines.
- Do not use Terraform provisioners as the normal Ansible integration.
- Use `prevent_destroy` for control-plane resources and any resource whose accidental deletion would compromise the test bench, even if service data is disposable.
- Data disks may be recreated, but replacement must still be explicit and observable.
- Keep Terraform state, Cloudflare tunnel credentials, certificates, and recovery material outside the repository.
- Require explicit approval for mutating Automation jobs.
- Fail closed on missing configuration, ambiguous targets, unsupported roles, or unavailable locks.

## Definition of done

- A new test bench can be created from Terraform without Bicep.
- Terraform manages the Azure and Cloudflare control-plane resources with no overlapping ownership.
- Ansible converges every VM role idempotently and supports check mode.
- APISIX, cloudflared, OAuth, OpenBao, Keycloak, Registry, and MCP routing are healthy.
- Secrets are delivered without appearing in Terraform state, command arguments, or logs.
- Automation can run read-only discovery and health checks through the Hybrid Worker.
- Restart/recovery and rollback acceptance tests pass.
- The old Bicep deployment can be destroyed after the new test bench is accepted.

## Initial deliverables

1. Terraform provider configuration and the `env/dev` stack are complete.
2. Foundation Terraform modules and outputs are deployed.
3. Ansible inventory contract and common role.
4. Private VM and managed identity modules.
5. Cloudflare provider configuration and ownership inventory.
6. Read-only Ansible verification playbook.
7. First end-to-end disposable test-bench deployment.
# Imperative AVM Resources

These resources are mandatory references for this implementation plan and must
be consulted before selecting modules, designing compositions, or writing
Terraform:

- [Terraform Resource Modules | AVM](https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-resource-modules/)
- [Terraform Pattern Modules | AVM](https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-pattern-modules/)
- [Terraform Utility Modules | AVM](https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-utility-modules/)
- [AI-Assisted IaC Solution Development | AVM](https://azure.github.io/Azure-Verified-Modules/experimental/ai-assisted-sol-dev/)
- [Terraform - Solution Development | AVM](https://azure.github.io/Azure-Verified-Modules/usage/solution-development/terraform/)
