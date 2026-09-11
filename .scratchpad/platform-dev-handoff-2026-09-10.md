# Platform Dev Handoff

Created: 2026-09-10

This is a secret-free handoff for the experimental Azure platform topology. It records the decisions, implementation state, deployment history, and remaining work so another session can continue without replaying the entire conversation.

## Executive status

The Azure control-plane foundation is deployed successfully. Semaphore UI is now
running on the dedicated private automation VM with PostgreSQL and a registered
runner. Workload runtime services are not yet bootstrapped.

Terraform currently manages 87 state resources. The latest successful apply completed with:

```text
Apply complete! Resources: 5 added, 5 changed, 0 destroyed.
```

The five private VMs and the replacement private PostgreSQL server now exist. Ansible still needs to install and configure the operating systems and services. Boundary host discovery and credential injection still need to be verified after the VMs are reachable through the intended private worker path.

## Repository and execution context

- Repository: `NineLivesDemo/ninelives-mcp-gateway`
- Working directory: `/home/rpl/Projects/NLAI/mcp-gateway-registry`
- Branch: `main`
- Azure subscription: `f1129652-3166-4f34-8d4c-5cf35bffbcdc`
- Azure tenant: `d5c40e9f-8e9d-4756-8285-02e973dfd6f1`
- Azure region: `westus3`
- Terraform version used: `1.16.1`
- AzureRM provider: `4.81.0`
- AzAPI provider: `2.12.0`
- Azure ModTM provider: `0.4.0`
- Random provider: `3.9.0`
- TLS provider: `4.4.0`

The working tree contains user/project changes beyond this handoff. Do not reset or clean unrelated files.

The detailed Semaphore deployment chronology and troubleshooting record is in
`.scratchpad/semaphore-autopilot/progress-log-2026-09-10.md`.

The initial Terraform-to-Ansible contract is implemented. The generated
`ansible_hosts` output is non-sensitive and contains only role groups, private
addresses, host names, and `ansible_user`. A real Ansible connectivity run is
now passing from the Semaphore runner against all five managed VMs using a
dedicated runner identity. The automation VM is excluded as the controller.
Never copy the operator's private key to the automation VM.

## Architecture decisions

### Ownership boundary

Terraform owns Azure control-plane infrastructure:

- Resource groups
- VNets, subnets, peering, routing, NSGs, and Bastion
- Private DNS zones and links
- Private VMs, NICs, managed identities, and role assignments
- Replacement PostgreSQL Flexible Server and private endpoint
- Retained-resource references where needed

Ansible owns VM-local and runtime configuration:

- OS packages and hardening
- Docker/Compose
- systemd units
- etcd, OpenBao, APISIX, Keycloak, and application services
- Certificates and runtime configuration
- Service health checks
- Bootstrap sequencing and application initialization

Do not move VM-local configuration into Terraform merely because the VMs now exist.

### Ansible execution and testing

#### Adopted integration pattern: HashiCorp Pattern 1

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

The decision is based on HashiCorp's current Terraform-Ansible guidance:
Ansible can manage the HCP Terraform workflow through the API, read a
deliberately shaped non-sensitive output contract without direct state-backend
access, and configure the hosts from the same workflow. This provides one
approved path from infrastructure provisioning to host convergence while
preserving Terraform state ownership and Ansible idempotent configuration.

Supporting mechanisms adopted or reserved:

- Use output-based dynamic inventory, not raw statefile inventory, for the
  Terraform-to-Ansible handoff.
- Use a pinned, reproducible Ansible execution environment containing
  `ansible-core`, required collections, `pytfe`, and required Python libraries.
- Reserve Terraform Actions for bounded, approved day-two operations rather
  than normal infrastructure provisioning or full Ansible convergence.
- Defer event-driven post-apply automation until the manually invoked
  workflow is reliable.

Rejected for the baseline:

- Terraform directly launching the complete Ansible platform through
  `ansible_playbook_run` or an equivalent provider resource.
- Terraform Actions as a generic Ansible runner.
- AAP-specific integration; AAP is not part of the target architecture.
- Making Semaphore or Ansible manage Terraform state or Azure resources
  outside the HCP Terraform workflow.

The portable Ansible assets are playbooks, roles, inventories, pinned
collections, execution-environment definitions, and Molecule scenarios.
Terraform remains responsible for Azure infrastructure and state, while
Ansible remains responsible for VM-local and runtime configuration. Molecule
tests Ansible content and delegated integration against reachable VMs; it does
not replace Terraform or own the lifecycle of the durable Azure topology.

The initial Docker Molecule scenario is passing. It tests the `platform_baseline` role through prepare, converge, idempotence, verify, and destroy, and only creates a disposable `ubuntu:24.04` test container.

The Terraform-to-Ansible handoff must publish only a deliberate,
non-sensitive host contract. Credentials remain execution-time inputs from
Managed Vault or the selected execution controller. Do not add the AAP
Terraform provider or Terraform-triggered AAP jobs unless a later decision
explicitly requires that integration.

### Network and ingress invariant

The intended request path is:

```text
Cloudflare Tunnel -> APISIX -> private workload upstream
```

There must be no direct public application endpoint, public workload VM address, or ingress bypass. The five workload VMs have no public IPs. Bastion's public access is intentional for management.

### Lifecycle isolation

Replacement infrastructure uses dedicated resource groups:

- `rg-platform-dev-network`
- `rg-platform-dev-services`
- `rg-platform-dev-app`
- `rg-platform-dev-data`

Existing groups remain outside the replacement lifecycle. In particular, do not import, delete, or otherwise manage the protected existing PostgreSQL server:

- Resource group: `rg-ai-access`
- Server: `psql-litellm-4bqvj62ztmxmi`
- FQDN: `psql-litellm-4bqvj62ztmxmi.postgres.database.azure.com`

Retained resources also include the existing Key Vault and ACR in `rg-ops`, plus other legacy resources documented in `platform/HANDOFF.md`.

Additional hard protection boundary: any database or ACA/ACAE resource that has
been running for months, and all AI resources, must not be modified or deleted.
The recently created replacement PostgreSQL server is the only database covered
by the experimental platform lifecycle.

## Deployed Azure resources

### Resource groups

```text
rg-platform-dev-network
rg-platform-dev-services
rg-platform-dev-app
rg-platform-dev-data
```

### VNets and address spaces

- Hub VNet: `10.60.0.0/16`
- Ingress/services VNet: `10.61.0.0/16`
- Application VNet: `10.62.0.0/16`

Subnets:

- Bastion: `10.60.250.0/26`
- Edge: `10.61.1.0/24`
- etcd: `10.61.2.0/24`
- OpenBao: `10.61.3.0/24`
- Private endpoints: `10.61.4.0/24`
- Application workload: `10.62.1.0/24`
- Keycloak: `10.62.2.0/24`

### Private VMs

| Role | Name | Resource group | VM size |
|---|---|---|---|
| Edge/APISIX | `vm-edge-platform` | `rg-platform-dev-services` | `Standard_D2ls_v7` |
| etcd | `vm-etcd-platform` | `rg-platform-dev-services` | `Standard_D2ls_v7` |
| OpenBao | `vm-openbao-platform` | `rg-platform-dev-services` | `Standard_D2ls_v7` |
| Application | `vm-application-dev` | `rg-platform-dev-app` | `Standard_D2ls_v7` |
| Keycloak | `vm-keycloak-dev` | `rg-platform-dev-app` | `Standard_D2ls_v7` |

All five VMs use private NICs only. Encryption-at-host is explicitly disabled in `terraform/modules/private-vm/main.tf` because the subscription does not have the `Microsoft.Compute/EncryptionAtHost` feature enabled.

The VM size was changed from `Standard_D2ds_v5` after Azure reported capacity restrictions in `westus3`. `Standard_D2ls_v7` was selected as the smaller option the operator identified as available in the region. Do not silently change to a larger SKU.

### Replacement PostgreSQL

The intended name `psql-platform-dev` was reserved by Azure after a failed create attempt even though no active resource appeared in `az resource list`. The service name-availability API reported it unavailable. The deployed replacement is therefore:

- Name: `psql-platform-dev-2`
- FQDN: `psql-platform-dev-2.postgres.database.azure.com`
- Resource group: `rg-platform-dev-data`
- Public network access: disabled
- Private endpoint: `psql-platform-dev-2-private-endpoint`

The PostgreSQL administrator password was supplied ephemerally from managed Vault during the Terraform plan/apply. It is not recorded in this handoff.

### Useful Terraform outputs

Use Terraform outputs for current IDs rather than copying stale values:

```bash
terraform -chdir=terraform/env/dev output
terraform -chdir=terraform/env/dev state list
```

Current output names include:

- `replacement_resource_group_ids`
- `platform_hub_virtual_network_id`
- `ingress_subnet_ids`
- `application_subnet_ids`
- `postgresql_server`
- `vm_resource_ids`
- `vm_network_interface_ids`

## Terraform files and important behavior

Primary environment:

- `terraform/env/dev/main.tf`
- `terraform/env/dev/variables.tf`
- `terraform/env/dev/outputs.tf`
- `terraform/env/dev/versions.tf`
- `terraform/env/dev/providers.tf`
- `terraform/env/dev/terraform.tfvars.example`

Wrappers:

- `terraform/modules/connectivity/`
- `terraform/modules/postgresql/`
- `terraform/modules/private-vm/`
- `terraform/modules/network-security/`
- `terraform/modules/managed-identities/`

Important safety settings:

- Connectivity AVM DDoS Protection Plan creation is explicitly disabled.
- PostgreSQL AVM firewall rules are explicitly `{}`.
- PostgreSQL public network access is disabled.
- Private VM public IP creation is disabled.
- Explicit module dependencies wait for resource groups and identities to exist.
- No existing protected PostgreSQL resource is in the replacement state.

Validation scripts:

```bash
terraform fmt -check -recursive terraform
terraform -chdir=terraform/env/dev validate
./scripts/validate-terraform-private-ingress.sh
git diff --check
```

The AVM emits upstream deprecation warnings about `retry.multiplier`; these are warnings, not an apply failure.

## Terraform deployment history

1. Initial isolated plan: `93 to add, 0 to change, 0 to destroy`.
2. Disabled the unwanted connectivity AVM DDoS default and PostgreSQL allow-all firewall default.
3. Revised isolated plan: `89 to add, 0 to change, 0 to destroy`.
4. Added four lifecycle-scoped resource groups and rewired modules.
5. New-group plan: `93 to add, 0 to change, 0 to destroy`.
6. First apply partially succeeded but hit Azure resource-group eventual-consistency races.
7. Added explicit `depends_on` relationships.
8. Vault credential access was fixed by correcting the KV path and AppRole policy.
9. Fresh plan with `psql-platform-dev` showed `10 to add, 5 to change, 0 to destroy`, but Azure reserved the requested PostgreSQL name and rejected VM creation because encryption-at-host was unavailable.
10. Disabled encryption-at-host and used the available name `psql-platform-dev-2`.
11. PostgreSQL and private endpoint were created successfully.
12. VM creation then failed because `Standard_D2ds_v5` had no westus3 capacity.
13. Changed all five VM defaults to `Standard_D2ls_v7`.
14. Final apply succeeded: `5 added, 5 changed, 0 destroyed`.

Always generate a fresh plan after changing variables or module configuration. Do not reuse a plan generated before the latest configuration change.

## Managed Vault state

Managed Vault is the active Vault-compatible secret backend for this topology.
Self-hosted OpenBao is the deferred implementation of the same
secret-management boundary. Managed Vault currently provides:

- AppRole authentication at `approle/`
- KV v2 engine at `secret/`
- Admin namespace context
- A PostgreSQL secret for the experimental platform at the UI path `secret/platform-dev/postgresql`

Important path detail:

The UI displayed the full API path as:

```text
/v1/admin/secret/data/secret/platform-dev/postgresql
```

The extra `secret/` path segment is part of the secret path. The working CLI command is:

```bash
vault kv get \
  -namespace=admin \
  -mount=secret \
  -field=password \
  secret/platform-dev/postgresql
```

The AppRole was:

- Name: `app-read-write`
- Authentication mount: `approle/`
- Token type: default-service
- Role ID and Secret ID are intentionally not recorded here.

The dedicated ACL policy is:

```text
platform-dev-postgresql
```

Its effective paths are:

```hcl
path "secret/data/secret/platform-dev/postgresql" {
  capabilities = ["create", "read", "update"]
}

path "secret/metadata/secret/platform-dev/postgresql" {
  capabilities = ["read"]
}
```

The initial policy was mistakenly created without the extra `secret/` path segment. That caused the 403. The corrected policy and a newly minted AppRole token fixed access.

Do not record or paste:

- Vault tokens
- AppRole Secret IDs
- PostgreSQL passwords
- The contents of local secret files

The operator bootstrap file is `~/.secrets/hashicorp`. The old PostgreSQL file is `~/.secrets/azure-litellmpsql`; it belongs only to the protected old server and must not be reused for the replacement.

## Active Vault decision

The managed Vault instance has removed the immediate secret-handling bottleneck
and its AppRole/KV workflow is validated. Use it for now despite the cost; any
future cost or platform concerns can be revisited explicitly.

The intended long-term split is:

- OpenBao on `vm-openbao-platform`: deferred as the self-hosted implementation;
  do not switch the active backend until a separate migration decision is made.
- Existing Azure Key Vault: retained for Azure-native integrations and existing secrets.
- Managed Vault: active Vault-compatible backend for the current topology.
- Ansible: consume scoped secrets during bootstrap without committing or printing them.

Ansible and Boundary may depend on Managed Vault for now. Keep the existing
Vault-compatible paths and policies documented so a later OpenBao migration remains
possible, but do not perform that migration as part of the current bootstrap.

## Boundary state

Boundary Cloud configuration was started conceptually:

- Boundary Cloud base: `7112b2f4-5266-491a-9481-424762f62009.boundary.hashicorp.cloud`
- Azure project scope: `p_2nQEFBx0Zh`
- NineLives scope: `o_L8rxc2Djsk`
- Dynamic Azure host catalog intended for the four replacement resource groups.
- Host set: `platform-dev-vms`
- Host filter: `tagName eq 'environment' and tagValue eq 'dev'`
- Preferred endpoint: `cidr:10.60.0.0/14`
- Sync interval: `300`
- SSH target: `platform-dev-ssh`
- Target type: SSH
- Port: `22`
- Client port: `2222`
- Maximum duration: `3600`
- Maximum connections: `-1`

Boundary initially reported no hosts because the replacement VMs did not yet exist. The
Boundary rollout is now deferred; it is not a prerequisite for runtime bootstrap.
Use Azure Bastion as the temporary management path and revisit Boundary after the
services are healthy and the Ansible workflow is established.

Boundary SSH targets require injected application credentials. Use a Vault-backed
credential library rather than placing private keys in Terraform variables or state. A separate PostgreSQL credential library/target should be used for port `5432` if database access through Boundary is required.

The dedicated Azure discovery service principal should have Reader access only to:

- `rg-platform-dev-network`
- `rg-platform-dev-services`
- `rg-platform-dev-app`
- `rg-platform-dev-data`

Do not broaden discovery to `rg-ai-access`, `rg-apps`, `rg-ops`, or legacy `rg-network`.

## Ansible handoff plan

The next engineer should inspect the Ansible tree and build a role-to-VM inventory mapping before changing infrastructure again.

Recommended sequence:

1. Establish private management access through Azure Bastion. Boundary is deferred
   until the runtime platform and Ansible workflow are established.
2. Verify each VM's private address, hostname, SSH reachability, and OS version.
3. Bootstrap common packages and hardening on all five VMs.
4. Bootstrap etcd and verify quorum/health.
5. Keep the self-hosted OpenBao implementation deferred; use Managed Vault for
   the current Vault-compatible secret workflow.
6. Bootstrap APISIX on the edge VM and configure only private upstreams.
7. Bootstrap the application VM and wire it to private PostgreSQL, etcd, Vault, and Keycloak.
8. Bootstrap Keycloak and defer provider-managed Keycloak resources until the service is healthy and reachable.
9. Configure Cloudflare Tunnel to reach APISIX without exposing workload VMs.
10. Run service health checks, private DNS checks, and end-to-end ingress checks.
11. Revisit Boundary host discovery and injected credentials after the services are healthy.

Runtime credentials should be injected at execution time. Avoid writing them into `group_vars`, committed files, Terraform variables files, shell history, process arguments, or logs.

## Immediate verification checklist

The following checks are still required:

```bash
terraform -chdir=terraform/env/dev plan -var='location=westus3' -var='postgres_name=psql-platform-dev-2'
./scripts/validate-terraform-private-ingress.sh
```

Azure checks:

- Confirm all five VMs are `Succeeded` and have no public IP resources.
- Confirm `vm-automation-platform` is `Succeeded`, has no public IP, and is
  reachable only through Bastion.
- Confirm the automation subnet's scoped NAT gateway provides outbound access
  without adding inbound exposure.
- Confirm Semaphore's `/api/ping` endpoint through a Bastion tunnel and confirm
  its runner remains registered.
- Confirm PostgreSQL `psql-platform-dev-2` is ready.
- Confirm PostgreSQL public network access remains disabled.
- Confirm the private endpoint and private DNS zone group are connected.
- Confirm NSGs and route-table associations are present.
- Confirm managed identities and intended role assignments are present.

Do not use the old PostgreSQL credential for the experimental platform server. Retrieve the platform credential through the approved secret workflow only.

## Known caveats

- Azure can reserve a PostgreSQL Flexible Server name after a failed create even when no active resource is listed. The deployed name is `psql-platform-dev-2`.
- Azure VM capacity is regional and SKU-specific. The current minimal choice is `Standard_D2ls_v7`; do not switch regions or upsize without an explicit decision.
- Encryption-at-host is disabled because the subscription feature is unavailable. This is an intentional subscription compatibility tradeoff for the experimental topology.
- The Terraform state is local under `terraform/env/dev/terraform.tfstate`. Treat it as sensitive because provider state can contain infrastructure metadata and potentially sensitive values.
- The Vault password was passed through an ephemeral environment variable during Terraform operations. Re-source the Vault bootstrap only when needed and do not print the variable.
- The current branch includes uncommitted project changes. Preserve them and inspect before committing.

## Safe continuation commands

From the repository root:

```bash
source ~/.secrets/hashicorp
export TF_VAR_postgres_administrator_password="$(
  vault kv get \
    -namespace=admin \
    -mount=secret \
    -field=password \
    secret/platform-dev/postgresql
)"
export TF_VAR_ssh_public_key="$(< ~/.ssh/id_ed25519.pub)"

terraform -chdir=terraform/env/dev validate
terraform -chdir=terraform/env/dev plan \
  -var='location=westus3' \
  -var='postgres_name=psql-platform-dev-2'
```

Only apply a newly reviewed saved plan. Never put the password in `terraform.tfvars`, the repository, a command-line `-var` argument, or a handoff document.

The Ansible baseline now pins `den_is.tools` at 26.8.3 and uses its `ripgrep` role for a common CLI binary. The Molecule scenario verifies collection installation, `rg`, idempotence, and clean teardown.

## Ansible tooling decisions

The first Docker Molecule scenario is intentionally bounded to disposable role testing: prepare, converge, idempotence, verify, and destroy. It does not manage or destroy Terraform-owned Azure VMs. Use `ansible-lint` for fast static quality checks, `ansible-playbook --syntax-check` and `--check` for broader playbooks, Molecule for focused role regression, and Semaphore for private Azure integration checks.

Mitogen was reviewed as a possible Ansible SSH performance optimization. It is deferred: the current five-host topology does not justify the added execution-layer compatibility risk, and the documented compatibility range must be validated against the pinned `ansible-core 2.20.8` before any controlled benchmark. Standard Ansible remains the default.

## Semaphore workflow status

The Azure Semaphore UI is reachable again through the Bastion tunnel at `http://127.0.0.1:3300`; `/api/ping` returns `pong`. Project creation is the next action, but the API correctly requires an authenticated admin session. No credentials were guessed, printed, or moved into the repository.

The Semaphore runner inventory is now clean: the active Azure automation runner was named in the UI, and the stale offline local-Compose registration was deleted.

## AAP cost discovery

The user identified that Ansible Automation Platform may be available at no license cost for homelab or single-user use. This reopens AAP as a viable experimental controller option from a licensing perspective. The current Semaphore deployment remains operational, but the controller decision should be revisited against AAP operational overhead, supported usage terms, runner model, and Terraform integration before further workflow investment.

## Managed AAP clarification

The user clarified that managed AAP is already configured and available. The self-hosted AAP/upstream platform is also license-free for this use case, with the platform repository publicly available. Therefore AAP is a ready alternative controller, not merely a hypothetical future option. Before creating Semaphore-specific projects and templates, compare the existing managed AAP path with the deployed Semaphore path for runner connectivity, Terraform/HCP orchestration, secret integration, and operational effort.

## HCP Terraform availability

The user confirmed HCP Terraform is available. The intended control-plane combination can therefore be evaluated directly: managed AAP orchestrates Ansible, HCP Terraform owns Terraform plan/apply and state, and shaped Terraform outputs feed the Ansible inventory. Semaphore remains a proven private runner fallback, but no Semaphore-specific project automation should be built until this AAP plus HCP Terraform path is compared and selected.

## Managed AAP setup status

The managed AAP instance is provisioned and exposes the standard admin login plus a one-time Red Hat account subscription-activation step. Credentials were intentionally not recorded in the repository or handoff. Do not paste AAP or Red Hat credentials into chat; use the AAP setup page and private browser session.

The user confirmed the managed AAP subscription is active through next year. AAP is therefore a fully viable primary controller option for the current platform effort, subject to workflow-fit validation rather than licensing availability.

## AAP SCM setup status

The managed AAP UI wizard successfully configured the organization/service-account setup and GitHub App SCM integration. The earlier concern about manually wiring enterprise GitHub authentication is resolved. Next step is to sync the AAP project and create or launch the read-only private connectivity job using the existing Terraform-generated inventory and dedicated runner SSH credential.

## HCP Vault integration candidate

The user confirmed HCP Vault is already online and available as an external secret manager. Prefer HCP Vault for the managed AAP credential lookup integration, including the dedicated SSH key and later runtime secrets, rather than storing private values directly in AAP. Preserve the existing Vault-compatible boundary so Managed Vault and self-hosted OpenBao remain interchangeable implementation options.

HCP Vault SSH signing foundation is configured: `ssh/` secrets engine, `aap-platform` CA-signed user-certificate role restricted to `azureuser` with 15-minute TTL and 1-hour maximum TTL, and a read-only signing policy exposed through a dedicated AppRole. AppRole credentials were stored locally in `~/.secrets/ansible-automation-platform` without printing them. Target VM CA trust and AAP Signed SSH credential wiring remain pending.

Vault Signed SSH research confirmed AAP has a native `HashiCorp Vault Signed SSH` credential type, which is preferable to KV lookup of a reusable private key. The Vault CA was trusted on all five target VMs; each sshd configuration was validated before reload. The AAP AppRole was adjusted for repeated job authentication with short-lived tokens and fresh credentials stored locally.

The earlier AppRole signing test failure was caused by reading variables from the local AAP secrets file with a parser that did not account for its export prefixes; the role and secret values were therefore empty. Using the correctly parsed local values, the AppRole login succeeded and the resulting short-lived token successfully signed an SSH certificate through ssh/sign/aap-platform. No secret values or tokens were printed.

## AAP credential and SCM integration episode

The managed AAP UI hid a credential-kind requirement: the existing GitHub PAT credential was a `token`-kind credential, while Project SCM fields require an `scm`-kind credential. AAP returned HTTP 400 (`Credential kind must be scm`) until a Source Control credential was assigned through the HTTPS repository URL. Project synchronization then completed successfully.

The Vault Signed SSH credential test also returned a transient HTTP 503 while the managed AAP controller task pod was unavailable; the pod recovered without operator action. No PAT, Vault token, AppRole secret, or private key was recorded in the handoff.

## Managed AAP private-network boundary finding

The first managed AAP `Registry Connectivity Check` job used the correct Terraform inventory and reached the SSH execution stage (`Identity added`), but all five private VM targets timed out at TCP port 22: `10.61.1.4`, `10.61.2.4`, `10.61.3.4`, `10.62.1.4`, and `10.62.2.4`. This is a network-path failure before SSH authentication, not a Vault credential or public-key failure. The managed AAP controller does not currently have a route into the Azure private VNets. Private Ansible execution must use a connected execution node/controller in Azure, a supported managed-AAP private-network integration, or the existing private Semaphore runner; exposing SSH publicly is not the preferred design.

## Managed AAP OpenShift control plane versus Azure execution node

Clarified that managed AAP runs its control plane on OpenShift, while the generated execution-node bundle is intended to install Receptor and Podman on the external Linux `vm-automation-platform`. The bundle successfully reached the VM through Azure Bastion, created the `receptor` user, and then stopped because the VM had no `podman` package candidate. Root cause: the VM Ubuntu APT sources used HTTP (`azure.archive.ubuntu.com:80`), and port 80 timed out. The VM therefore had no usable package-repository egress even though Bastion SSH access worked. The remediation is to use HTTPS Ubuntu archive sources and install Podman over port 443 before rerunning the supplied Receptor bundle.

## Official execution-node guidance and current blocker

The official Red Hat AAP 2.6 documentation describes execution nodes as part of the Receptor mesh and directs administrators to add the execution node through AAP, install the generated node bundle, and use instance groups to determine where jobs run. Relevant references: [Add execution nodes](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/installing_containerized_ansible_automation_platform/assembly-adding-execution-nodes), [Run jobs on execution nodes](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/administering_automation_controller/controller-configure-instance-groups), and [Configure instance groups from the API](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/administering_automation_controller/controller-configure-instance-groups).

Following that guidance, instance `vm-automation-platform` was configured with listener TCP/27199, `peers_from_control_nodes=true`, and assigned to the `controlplane` instance group. However, the managed AAP API exposes no Receptor address for its managed control instance, the execution instance has zero configured peers, and the regenerated official install bundle contains no Receptor backend. The Azure node therefore cannot form a mesh connection from the supplied bundle. Its Receptor service was disabled after installation to prevent a crash loop caused by `Nothing to do - no backends are running.` Do not add an invented backend or expose SSH publicly; the remaining requirement is a provider-supported managed-AAP private execution/mesh path or confirmation that external execution nodes are not supported for this tenant.


## Managed AAP mesh API evidence

A subsequent API inspection clarified the topology: AAP instance 2 has `reverse_peers: [1]`, `peers: []`, `peers_from_control_nodes=true`, and a canonical external Receptor address of `vm-automation-platform:27199`. The managed control instance has no Receptor address of its own. AAP reports the exact error `Instance vm-automation-platform is not in the receptor mesh`, with `last_seen=null`, `capacity=0`, and state `unavailable`. This confirms the remaining failure is that the managed control plane cannot establish the configured Receptor connection to the Azure node; it is not an instance-group association problem.


## Official bundle backend check

Inspected the quarantined AAP-generated bundle and the installer playbook. The bundle contains the Receptor TLS/work keys, listener/work-command variables, inventory, and `ansible.receptor` collection requirement, but no backend, peer, or control-plane endpoint definition. The installer does not generate a missing peer from the bundle contents. This rules out a simple rerun or package-install correction as the fix for the current mesh error.

## Fresh account and managed AAP retry status

Updated 2026-09-10 22:22 EDT.

The operator created a new Red Hat account, a new Azure tenant/subscription
context, and a new managed AAP instance. This is a clean retry of the managed
AAP path after the previous instance became unstable and failed to connect its
external execution node to the Receptor mesh.

At the time of this update, the new account, tenant, subscription, managed AAP
endpoint, instance IDs, and Azure resource identifiers have not yet been
recorded in this handoff. Do not copy the previous tenant, subscription,
resource IDs, managed AAP endpoint, credentials, or execution-node bundle
configuration into the new environment.

The following findings remain historical evidence from the previous
environment and must be revalidated rather than assumed:

- The old managed AAP control plane could not reach the private Azure VM
  subnets.
- The old external execution instance remained unavailable with no Receptor
  backend/peer generated in its bundle.
- The old Azure VNets and private VMs were healthy and had working
  VM-to-VM/private-runner connectivity.
- Public SSH exposure remains rejected as the default remediation.

The next retry must first capture, without recording secrets:

1. New Azure tenant ID, subscription ID, region, and the resource groups/VNet
   used by the new platform.
2. New managed AAP endpoint, instance state, control-plane capacity, and
   whether the product exposes a supported private-network or external
   execution-node integration.
3. The exact execution-node/Receptor configuration generated by the new
   instance, including backend/peer definitions and required listener
   direction.
4. A fresh network-path test from the intended execution node to every private
   target before launching a full connectivity job.

Until those facts are captured, this handoff is current for the historical
investigation and AAP 2.7 bundle inspection, but not yet an operational
handoff for the new environment.
