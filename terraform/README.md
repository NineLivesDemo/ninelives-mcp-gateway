# Terraform platform

The Terraform implementation is organized as a thin environment root and
repository-owned compositions:

- `env/dev/` contains deployment-specific configuration.
- `modules/platform/` composes shared platform landing-zone capabilities.
- `modules/connectivity/` composes the platform landing-zone hub and shared
  connectivity services.
- `modules/platform-services/` composes the private ingress and platform
  services VNet.
- `modules/application-landing-zone/` composes private workload VNets.
- `modules/private-dns-zone/` composes private-link DNS zones and VNet links.
- `modules/postgresql/` composes the Terraform-owned PostgreSQL service.
- `modules/managed-identities/` composes runtime identities and explicit RBAC
  scope maps.
- `modules/private-vm/` composes private VM foundations; Ansible owns the
  services installed on those VMs.
- `modules/network-security/` composes explicit inbound NSGs and per-subnet
  route tables for the private VM subnets. Its default route collections are
  empty so Azure system routes remain in effect until a firewall or other
  controlled next hop is explicitly introduced.

The development environment creates four new lifecycle-scoped resource groups:
`rg-platform-dev-network`, `rg-platform-dev-services`, `rg-platform-dev-app`,
and `rg-platform-dev-data`. Existing `rg-network`, `rg-apps`, `rg-ai-access`,
and `rg-ops` resources are referenced or preserved rather than reused as
containers for the replacement environment.

The disposable development environment does not create an Azure DDoS
Protection Plan. Bastion's public IP is retained as an intentional management
endpoint, while workload VMs have no public IPs. PostgreSQL public network
access and firewall rules are both disabled; access is through its private
endpoint and private DNS zone.

Terraform owns Azure control-plane infrastructure. Ansible owns VM-local
runtime configuration and services.

Secret handling is staged. The initial deployment consumes values already
seeded in Key Vault through managed identity and narrowly scoped access. Those
runtime values are not exposed through Terraform outputs or logs. A later
runtime configuration can move application secret consumption to OpenBao while
retaining Key Vault for bootstrap, unseal, and Azure-native use cases where it
remains the appropriate boundary.

The replacement PostgreSQL administrator password is supplied through a
protected ephemeral environment variable at deployment time. Terraform does
not fetch the value from Key Vault, output it, or log it. Operators may seed
that environment variable from an approved secret-management workflow before
running Terraform.

This follows the Cloud Adoption Framework distinction between a platform
landing zone and application landing zones. The initial disposable environment
models that distinction within one Azure subscription using separate resource
groups, VNets, and ownership boundaries; it does not require the full
management-group and subscription-vending accelerator on day one.

The development environment exports only non-secret resource IDs, subnet IDs,
network interface IDs, and PostgreSQL server metadata for Ansible handoff. It
does not export passwords, Key Vault values, or runtime credentials.

Runtime RBAC is opt-in and resource-ID driven. Supplying the existing Key Vault
ID creates per-secret `Key Vault Secrets User` assignments for the application
and Keycloak identities; supplying the existing ACR ID creates only `AcrPull`
for the application identity; supplying the OpenBao unseal key ID creates only
the corresponding crypto-user assignment for platform operations. Leaving
these IDs unset creates no role assignments.
