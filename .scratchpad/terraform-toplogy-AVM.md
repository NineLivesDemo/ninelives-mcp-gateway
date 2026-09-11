Act as the Terraform/AVM specialist for this repository. Thoroughly inspect the existing planning documents and platform topology, especially .scratchpad/terraform-ansible-directory-tree.md, .scratchpad/terraform-ansible-migration-plan.md, docs/terraform-import/EXPORTED-ARCHITECTURE.md, docs/terraform-import/exported-resources.json, and platform/azure/README.md. Then research the authoritative Azure Verified Modules website indexes and linked Terraform Registry documentation. Produce a concrete AVM selection matrix for the single disposable env/dev SaaS test bench, covering foundation, data, infrastructure, and integrations. For each candidate, state the exact AVM module name/source, published/proposed status if discoverable, why it fits, major ownership/input/output considerations, and where a plain azurerm data source/resource or external provider is preferable. Check pattern modules before resource modules. Do not edit files, do not run Terraform or query Azure, and do not use GitHub source pages as the primary AVM reference. Return actionable findings with authoritative URLs.
AVM selection matrix — disposable env/dev SaaS test bench
Review basis: repository planning documents, canonical exported topology, and the AVM Terraform pattern/resource indexes and Terraform Registry documentation. No Azure queries, Terraform commands, or repository edits were performed.

The target is a private VM-based platform in westus3, not an ACA deployment:

VNet 10.60.0.0/16
Edge, etcd, OpenBao, application, and Keycloak private VMs
Bastion for operator access
NAT-controlled egress
Key Vault and managed identities
Existing ACR dependency and Terraform-owned PostgreSQL
External MongoDB Atlas M10 cluster
Cloudflare Tunnel and Keycloak provider integrations
Ansible-owned VM-local services and configuration
The AVM framework documentation states that modules are still published as pre-release versions until AVM reaches GA. Therefore, “published” below means listed in the official AVM index and available in the Terraform Registry; it does not imply a stable 1.0.0 contract.

1. Authoritative AVM references
These should be treated as the primary module-discovery sources:

AVM Terraform Pattern Modules index
AVM Terraform Resource Modules index
AVM Terraform Utility Modules index
AVM Terraform solution-development guidance
AVM Terraform module proposal process
Relevant design-pattern references:

ALZ Terraform pattern module
ALZ connectivity hub-and-spoke pattern

Cloud Adoption Framework: platform and application landing zones:
https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/?tabs=conceptual%2Cplatvsapp
The ALZ modules are useful examples of capability-oriented composition, but they are not appropriate as the top-level implementation for this small disposable test bench.

2. Pattern-first assessment
Pattern candidate	Status observed	Recommendation
Azure/avm-ptn-alz/azurerm	Published; Registry latest observed 0.21.0	Do not use. It introduces management-group, policy, archetype, and ALZ provider complexity that is outside this single-subscription test bench.
Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm	Published; latest observed 0.17.5	Use as the target connectivity composition. The current platform VNet is a consolidated starting point, but APISIX is intended to route many business workloads. Model a shared connectivity hub plus an initial ingress/platform-services spoke and workload spoke. Disable unused firewall, VPN, ExpressRoute, DDoS, and other capabilities for the disposable dev deployment.
Azure/avm-ptn-network-private-link-private-dns-zones/azurerm	Published; latest observed 0.23.2	Conditional use. Appropriate if the implementation creates several Azure Private Link DNS zones and links them consistently. For the current single PostgreSQL private endpoint, the individual resource modules are simpler and clearer.
Azure/avm-ptn-aca-lza-hosting-environment/azurerm	Published; latest observed 0.1.0	Do not use for the primary bench. The repository explicitly identifies ACA as an alternate/rollback path. The desired architecture is VM-hosted applications and services.
Other indexed patterns	Published candidates exist for AKS, AVD, monitoring, virtual WAN, and landing-zone capabilities	No direct match. None represents this private VM + Bastion + Ansible + Cloudflare SaaS test bench.
Conclusion: The published connectivity pattern matches the platform landing-zone
hub portion of the future business-platform topology. Use a repository-owned
platform/connectivity composition around it, then consume the published AVM VNet
resource module for the independently owned ingress/platform-services VNet and
application landing-zone VNets, including their explicit hub peerings. Do not
treat the pattern's hub-mesh input as a substitute for application landing
zones, and do not create one wrapper per Azure resource.

The pattern is not a replacement for APISIX. It supplies the shared hub
capabilities that let the Cloudflare Tunnel/APISIX ingress application landing
zone reach workload application landing zones over private connectivity. Spoke
VNets use the AVM VNet resource module and explicit peering. APISIX routes
remain application contracts; VNet peering and routing remain network
contracts. Prefer the pattern's own hub capabilities for Bastion, NAT, route
tables, firewall, and shared DNS where enabled; do not create duplicate
standalone resources for those hub-owned capabilities.

Ingress invariant: all externally initiated application traffic must traverse
`Cloudflare Tunnel -> APISIX -> private workload upstream`. Workload spokes and
application modules must not create public application endpoints or alternate
direct ingress paths. Private connectivity between APISIX and workloads is
allowed; direct external reachability is not.

3. Foundation matrix
Capability	Recommended AVM module/source	Status/version observed	Why it fits	Major ownership, inputs, and outputs	Prefer plain AzureRM/data source when
Resource groups	Azure/avm-res-resources-resourcegroup/azurerm	Published; 0.4.0	Standardizes naming, tags, locks, and resource-group-level settings.	Inputs: name, location, tags, locks. Output: resource-group ID/name/location. The foundation composition should own rg-network, rg-ops, and the application/keycloak groups only if the new bench owns them.	Use azurerm_resource_group for a very small disposable group when the module adds no useful behavior and a direct resource makes lifecycle ownership more obvious. Do not manage an existing shared group as new ownership.
VNet and subnets	Azure/avm-res-network-virtualnetwork/azurerm	Published; 0.22.2	Direct match. It manages the VNet, nested subnets, peerings, subnet NSG/route/service-endpoint associations, and supports static addressing.	Inputs: parent_id, name, location, static address_space, nested subnets, optional DNS servers/tags. Outputs: VNet ID/name and subnet IDs. Use static CIDRs because AVM IPAM does not support westus3. Do not create sibling subnet modules for the same VNet.	Use azurerm_subnet only for an exceptional subnet that must have a separate lifecycle. Avoid mixing sibling subnet ownership with the AVM VNet module.
NSGs	Azure/avm-res-network-networksecuritygroup/azurerm	Published; 0.5.1	Suitable for explicit private-tier ingress/egress rules.	Inputs: resource group, location, security rules, tags/locks. Output: NSG ID. Attach through subnet or NIC ownership deliberately. Define rules for Bastion management, east-west platform traffic, private endpoints, and controlled egress.	Use azurerm_network_security_group when rules are highly bespoke and the module's generalized rule map would obscure security review. Do not let both the VNet module and standalone NSG resources associate the same subnet.
NAT Gateway	Azure/avm-res-network-natgateway/azurerm	Published; 0.3.2	Matches deterministic outbound access for private VMs.	Inputs: parent resource group, location, public IP/prefix association, subnet associations, idle timeout. Output: NAT Gateway ID and public IP association data. The public egress IP is control-plane infrastructure, not a VM public IP.	Use azurerm_nat_gateway and azurerm_subnet_nat_gateway_association if the module cannot express the required association layout or if a shared NAT is externally owned.
Bastion	Azure/avm-res-network-bastionhost/azurerm	Published; 0.9.0	Directly supports the private break-glass access path.	Inputs: AzureBastionSubnet ID, Standard SKU, public IP, tunneling, scale units, location. Outputs: Bastion ID/name/public IP. Keep the Bastion public IP on Bastion only; no VM public IPs.	Use azurerm_bastion_host when tunneling or other current API properties are not exposed as needed. Confirm the module's support for the required Standard SKU features before implementation.
Private DNS zones	Azure/avm-res-network-privatednszone/azurerm	Published; 0.5.0	Suitable for explicit zones such as privatelink.postgres.database.azure.com and VNet links.	Inputs: parent_id, domain_name, VNet links, records, optional RBAC/locks. Outputs: zone ID and links. Note that the current module uses AzAPI internally; that is an implementation detail, not a reason to use AzAPI directly in the composition.	Use azurerm_private_dns_zone and azurerm_private_dns_zone_virtual_network_link where the zone is simple and the team wants a smaller provider surface.
Managed identities	Azure/avm-res-managedidentity-userassignedidentity/azurerm	Published; 0.5.2	Useful for stable identities for VM secret-sync, automation, and narrowly scoped workload access.	Inputs: resource group, location, name, tags, optional role assignments/federated credentials. Outputs: client ID, principal ID, resource ID, tenant ID. Keep system-assigned identities on the VM/Automation resource where that is the natural ownership boundary.	Use azurerm_user_assigned_identity directly if no role assignments or federated credentials are needed and a standalone identity module adds no value.
Role assignments	Azure/avm-res-authorization-roleassignment/azurerm	Published; 0.3.1	Provides a structured role-assignment map and supports Azure resource-manager scopes.	Inputs: principal ID, scope, role definition ID/name, conditions, description, service-principal checks. Outputs are assignment-oriented. Use for repeated, map-driven least-privilege grants.	Prefer direct azurerm_role_assignment for one-off assignments where explicit scope and role are easier to audit. In particular, avoid hiding the individual Key Vault secret scopes and ACR pull scope behind an overly broad map.
Foundation boundary

The foundation composition should own:

Resource groups.
VNet and all subnets.
NSGs and their associations.
NAT and controlled egress.
Bastion and its public IP.
Private DNS zones and VNet links.
User-assigned identities that have an independent lifecycle.
Explicit RBAC assignments.
The connectivity pattern should be the sole owner of hub-level Bastion, NAT, route tables, firewall, and shared DNS capabilities that it enables. The VNet module should be the sole owner of each spoke VNet and its nested subnet resources. The VM module should be the sole owner of VM-associated NICs where its network_interfaces input is used. Resource modules such as Key Vault and PostgreSQL should own their own private endpoints, diagnostics, and RBAC through nested inputs where supported.

4. Data and private-link matrix
Capability	Recommended AVM module/source	Status/version observed	Recommendation
Key Vault	Azure/avm-res-keyvault-vault/azurerm	Published; 0.11.0	Use. This is the strongest AVM fit in the data layer. It supports vault configuration, RBAC, network ACLs, private endpoints, keys, locks, and related wiring. Configure RBAC authorization and public_network_access_enabled = false.
OpenBao unseal key	Same Key Vault module	Same	Use as a child capability of the Key Vault composition. Terraform may own the key object and its RBAC, but not secret values, OpenBao tokens, private keys, or runtime configuration. Outputs should expose the key ID/version only where operationally required.
Storage account for locks/audit	Azure/avm-res-storage-storageaccount/azurerm	Published; 0.10.0	Use if operations storage remains in scope. Configure private access, TLS, appropriate replication for disposable data, containers for locks and audit, and narrow worker identity permissions.
Storage containers	Same storage module where supported; otherwise azurerm_storage_container	Published parent module	Keep storage-account ownership in AVM. Use direct AzureRM child resources if the module does not expose the exact container/lifecycle inputs needed by the runbook design.
Existing ACR	Azure/avm-res-containerregistry-registry/azurerm exists; latest observed 0.8.0	Do not create it in this bench. The exported architecture identifies cr4bqvj62ztmxmi as an existing dependency. Use data.azurerm_container_registry or an equivalent ID variable. Terraform should own only the application VM's AcrPull assignment if that is part of the new boundary.	
PostgreSQL Flexible Server	Azure/avm-res-dbforpostgresql-flexibleserver/azurerm exists; latest observed 0.2.3	Use and own in Terraform. The server is an Azure resource in the target bench, even if the current reference deployment already has one. Create the server, its Keycloak database boundary, private endpoint, and private DNS zone/link. Database passwords and application credentials remain outside Terraform state.	
Private endpoint	Azure/avm-res-network-privateendpoint/azurerm	Published; 0.2.0	Use only for generic endpoints not already owned by a selected resource module. The PostgreSQL and Key Vault modules already expose private-endpoint resources; configure those modules directly first to avoid duplicate ownership.
Private Link DNS bundle	Azure/avm-ptn-network-private-link-private-dns-zones/azurerm	Published; 0.23.2	Use for the shared multi-service DNS bundle once Key Vault, PostgreSQL, Storage, and other private endpoints are in scope. Let resource modules create their endpoint and zone-group wiring; let this pattern own the shared zone/link set.
Individual private DNS zone	Azure/avm-res-network-privatednszone/azurerm	Published; 0.5.0	Prefer for the current single-service case. It makes ownership and the PostgreSQL zone link explicit.
Disk encryption set	Azure/avm-res-compute-diskencryptionset/azurerm	Listed in official resource index	Optional. Use only if the test-bench security baseline requires a separately managed encryption set. For disposable managed disks, the VM module's disk encryption/security settings may be sufficient.
Managed disks	Azure/avm-res-compute-disk/azurerm	Published; 0.4.0	Conditional. Use for explicitly separate disposable data disks. Prefer VM-owned OS/data disk inputs when disks have no independent lifecycle.
Data ownership decisions

For this repository, the cleanest data-layer contract is:

Terraform creates: Key Vault integration and policy, the OpenBao unseal key, Terraform-owned PostgreSQL Flexible Server, storage account if retained, private endpoints, private DNS zones/links, and narrowly scoped RBAC. Existing Key Vault secret values are pre-seeded and are not read or managed as Terraform values.
Terraform references: the existing ACR only.
Initial Ansible/operator workflow retrieves the pre-seeded Key Vault values through managed identity and uses them to bootstrap the platform. A later configuration stage moves runtime secret consumption to OpenBao where appropriate; Key Vault remains for bootstrap, unseal, and Azure-native use cases that should not be moved.
No secret values should be Terraform variables, outputs, .tfvars, cloud-init, or ordinary state-backed resources.
The disposable-data policy permits clean recreation of PostgreSQL. The existing ACR remains a referenced shared dependency. MongoDB Atlas and Grafana Cloud are outside Azure and remain external runtime dependencies.

5. Infrastructure matrix
Infrastructure capability	Recommended AVM module/source	Status/version observed	Fit and ownership guidance
Generic Linux VM foundation	Azure/avm-res-compute-virtualmachine/azurerm	Published; 0.21.0	Use for all five VMs. It manages VM foundations, NICs through network_interfaces, identities, OS/data disks, boot diagnostics, and extensions. Create one repository composition per role (edge, etcd, openbao, app-host, keycloak) or one map-driven platform VM composition—not sibling NIC modules.
VM NICs	Owned through the VM module's network_interfaces input	Same	Do not create separate avm-res-network-networkinterface or azurerm_network_interface resources for those VMs. The module must own static private IP configuration, subnet association, accelerated networking where applicable, and NSG association consistently.
VM extensions	Owned through the VM module's extensions input where possible	Same	Use extensions only for Azure control-plane agents such as Hybrid Worker or carefully bounded bootstrap mechanisms. Do not use extensions to render Compose, systemd, APISIX, cloudflared, OpenBao, or application secrets; those remain Ansible-owned.
OS disks	VM module input	Same	Use the VM module's OS disk settings for the disposable operating-system disks. Pin the Ubuntu 24.04 image and VM sizes from the current topology.
Separate data disks	Azure/avm-res-compute-disk/azurerm, or VM module data-disk inputs	Published; 0.4.0	Use a separate disk module only when a disk has a meaningful independent lifecycle. OpenBao Raft and application data are explicitly disposable for this bench.
Automation Account	Azure/avm-res-automation-automationaccount/azurerm	Published; 0.2.0	Use for the Automation Account. Registry documentation exposes inputs for hybrid worker groups/workers, modules, schedules, runbooks, connections, certificates, and credentials. Verify the exact current schema for the extension-based Hybrid Worker resources before implementation.
Hybrid Worker groups/workers	Automation AVM child inputs first; AzureRM second; AzAPI only for a demonstrated gap	Published parent module; child coverage must be verified	The AVM module appears to expose automation_hybrid_runbook_worker_groups and automation_hybrid_runbook_workers. Use those if they support the required extension-based Hybrid Worker model. If not, use direct AzureRM resources where available. Isolate any AzAPI resources by API version and document the gap.
Hybrid Worker VM extension	VM AVM extensions input first; AzureRM VM extension second	VM AVM published	The extension belongs to the VM foundation that owns the VM. Do not create a separate “worker VM” abstraction that duplicates VM ownership. The extension's secrets/configuration must be delivered through approved identity/Key Vault mechanisms, not embedded in Terraform.
Operations lock/audit storage	Storage AVM module	Published; 0.10.0	Use only if the read-only/mutation runbook architecture remains in the initial scope. The migration plan states that Automation is not required for the initial pure-Ansible path, so this should be capability-gated rather than mandatory.
Ansible inventory outputs	No AVM	N/A	Terraform outputs should expose non-secret VM IDs, private IPs, hostnames, subnet IDs, and identity IDs. A repository script can transform those outputs into ansible/inventory/generated/platform.yml; do not expose private keys or secret values.
VM role-specific decisions

Edge VM: VM AVM foundation only. APISIX and cloudflared packages, Compose/systemd units, route rendering, tunnel credentials, and certificates remain Ansible-owned.
etcd VM: VM AVM foundation only. mTLS files, etcd configuration, service state, and health checks remain Ansible-owned.
OpenBao VM: VM AVM foundation plus identity/RBAC needed for Azure Key Vault auto-unseal. OpenBao Raft state and configuration remain Ansible-owned.
Application VM: VM AVM foundation plus ACR pull role assignment and narrowly scoped Key Vault access. Registry, auth-server, MCP gateway, Compose, and local files remain Ansible-owned.
Keycloak VM: VM AVM foundation plus access to the Terraform-owned PostgreSQL private endpoint and explicitly scoped Key Vault secrets. Keycloak bootstrap and provider resources occur only after Ansible has made the service available.
6. Integrations matrix
Integration	Implementation	AVM status	Recommendation and boundary
Cloudflare Tunnel	Cloudflare Terraform provider, including cloudflare_zero_trust_tunnel_cloudflared and explicitly owned Access/Zero Trust/DNS resources	Not an AVM concern	Use the Cloudflare provider. Terraform owns Cloudflare account control-plane objects. Ansible owns the cloudflared service and local tunnel configuration on the edge VM. Do not use an Azure AVM module.
Cloudflare DNS	Cloudflare Terraform provider	Not AVM	Manage only records explicitly assigned to this repository. Avoid changing account-wide or pre-existing DNS ownership implicitly.
Keycloak realms/clients/roles	Keycloak Terraform provider	Not an AVM concern	Use after Ansible bootstrap and health verification. Keep Keycloak provider resources in terraform/modules/integrations/keycloak. Do not use Terraform to install or configure the Keycloak VM runtime.
Existing MongoDB	External provider, data source, or Ansible/operator secret workflow	Not an AVM concern	Do not create an Azure MongoDB resource. The architecture marks MongoDB external. Keep its URL and credentials out of Terraform state; pass only through the approved runtime secret workflow.
Grafana Cloud	External Grafana Cloud provider or operator-managed OTLP configuration	Not an Azure AVM concern	Do not select Azure Managed Grafana. Grafana Cloud is the external observability platform; Terraform may manage only explicitly owned Grafana Cloud dashboards, alerting, folders, or data sources if that provider boundary is approved. Keep API tokens and OTLP credentials in the secret workflow.
Existing ACR pull access	AzureRM role assignment or AVM role-assignment module	AVM available	Assign AcrPull only to the application VM identity and only at the ACR scope. Use a direct azurerm_role_assignment if that makes the least-privilege grant easier to review.
Key Vault secret access	Direct AzureRM role assignments or AVM role-assignment module	AVM available	Prefer explicit per-secret-scope assignments where required by the existing design. Do not grant whole-vault access merely because it is easier for a module input map.
Ansible handoff	Terraform outputs plus local generation script	Not AVM	Keep output contract non-secret: VM IDs, private IPs, subnet IDs, resource IDs, identity IDs, and DNS names. Ansible remains the sole owner of host-local configuration.
7. Where plain AzureRM is preferable
AVM should not be used mechanically. The following are good direct-resource/data-source candidates:

Existing ACR

Use data.azurerm_container_registry or an explicit registry ID variable because the current bench consumes an existing shared registry.
Assign AcrPull only to the application VM identity.

MongoDB Atlas

Keep the MongoDB Atlas M10 cluster outside Azure AVM and outside the Azure Terraform composition.
Pass its connection details through the approved secret workflow; do not place its URI or credentials in Terraform state.
One-off role assignments

azurerm_role_assignment is often clearer than a generalized role-assignment module for a single ACR pull or individual Key Vault secret grant.
Keep scope, principal, role, condition, and justification visible in the composition.
Simple private DNS links

If only PostgreSQL requires a private DNS zone and link, direct AzureRM resources may be easier to audit than the larger private-link pattern.
Exceptional VM extensions

Use the VM AVM extension input first.
Use azurerm_virtual_machine_extension directly if the module does not expose the exact handler settings, protected settings, or version needed.
Use AzAPI only after documenting a provider/module gap.
Simple resource groups

The resource-group AVM is appropriate when locks, tags, or standardized behavior are useful.
A plain azurerm_resource_group is reasonable for a disposable, single-purpose group with no additional behavior.
VM-local configuration

Do not use Terraform provisioners, VM extensions, or custom data for Compose, systemd, APISIX, cloudflared, etcd, OpenBao, Keycloak, or application runtime configuration.
Ansible is the correct owner.
Cloudflare, Keycloak, and MongoDB Atlas

Cloudflare, Keycloak, and Grafana Cloud use their respective providers. MongoDB Atlas remains an external provider or operator-controlled secret workflow.
8. Proposed repository composition
The existing target tree is directionally correct. The recommended dependency graph is:

Plain text
terraform/env/dev
└── module.platform
    ├── module.foundation
    │   ├── resource groups
    │   ├── virtual network + subnets
    │   ├── NSGs
    │   ├── NAT
    │   ├── Bastion
    │   ├── private DNS
    │   └── identities/RBAC
    ├── module.data
    │   ├── Key Vault + key
    │   ├── operations storage (optional)
    │   ├── existing ACR data reference
    │   ├── existing PostgreSQL data reference
    │   └── private endpoints/DNS
    ├── module.infrastructure
    │   ├── edge VM
    │   ├── etcd VM
    │   ├── OpenBao VM
    │   ├── application VM
    │   ├── Keycloak VM
    │   └── optional Automation/Hybrid Worker capability
    ├── module.apps
    │   ├── Registry deployment contract
    │   ├── auth-server deployment contract
    │   └── MCP gateway deployment contract
    └── module.integrations
        ├── Cloudflare provider resources
        └── Keycloak provider resources
The platform composition should expose capability switches such as:

enable_bastion
enable_automation
enable_operations_storage
enable_postgresql_private_endpoint
enable_cloudflare
enable_keycloak_provider_resources
This is preferable to adding separate environment roots or forcing every optional service into the initial disposable deployment.

9. Concrete initial selection
For the first implementation pass, select:

Foundation

Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm as the target hub-and-spoke connectivity composition, with unused capabilities disabled for dev.
Azure/avm-res-resources-resourcegroup/azurerm
Azure/avm-res-network-virtualnetwork/azurerm for workload and platform-service spokes outside the connectivity pattern.
Azure/avm-res-network-networksecuritygroup/azurerm for spoke-tier security rules.
Azure/avm-res-network-natgateway/azurerm only where egress is not owned by the hub pattern.
Azure/avm-res-network-bastionhost/azurerm only where Bastion is not enabled through the hub pattern.
Azure/avm-res-network-privatednszone/azurerm for explicit workload private DNS ownership.
Azure/avm-res-managedidentity-userassignedidentity/azurerm
Direct AzureRM or Azure/avm-res-authorization-roleassignment/azurerm, selected per assignment clarity.
Data

Azure/avm-res-keyvault-vault/azurerm
Azure/avm-res-dbforpostgresql-flexibleserver/azurerm for the Terraform-owned Keycloak database.
Azure/avm-res-network-privateendpoint/azurerm only for endpoints not owned by another selected resource module
Azure/avm-res-storage-storageaccount/azurerm, capability-gated
Direct data source for the existing ACR
Azure/avm-ptn-network-private-link-private-dns-zones/azurerm only if the implementation creates a multi-service private-link DNS bundle.
Infrastructure

Azure/avm-res-compute-virtualmachine/azurerm for all five VMs.
Azure/avm-res-compute-disk/azurerm only for independently managed disposable data disks.
Azure/avm-res-automation-automationaccount/azurerm only when Automation is included in the initial capability set.
VM AVM extensions first, direct AzureRM extensions second, AzAPI only for a verified Hybrid Worker gap.
Integrations

Cloudflare provider.
Keycloak provider after Ansible bootstrap.
External MongoDB Atlas and Grafana Cloud reference/secret workflows.
AzureRM or AVM role assignments for ACR and Key Vault access.
This selection preserves the repository's intended ownership model, uses the connectivity pattern before resource modules, keeps PostgreSQL inside the Azure Terraform boundary, and leaves MongoDB Atlas, Grafana Cloud, and VM-local runtime state outside Azure AVM.
