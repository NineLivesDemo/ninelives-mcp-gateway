# Terraform and Ansible Directory Tree

# Imperative AVM Resources

These resources are mandatory references for this implementation plan and must
be consulted before selecting modules, designing compositions, or writing
Terraform:

- [Terraform Resource Modules | AVM](https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-resource-modules/)
- [Terraform Pattern Modules | AVM](https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-pattern-modules/)
- [Terraform Utility Modules | AVM](https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-utility-modules/)
- [AI-Assisted IaC Solution Development | AVM](https://azure.github.io/Azure-Verified-Modules/experimental/ai-assisted-sol-dev/)
- [Terraform - Solution Development | AVM](https://azure.github.io/Azure-Verified-Modules/usage/solution-development/terraform/)

This models the target layout before implementation begins. Existing Bicep and
platform runtime directories remain available as reference until the replacement
bench is accepted.

## Existing relevant tree

```text
.
├── .azure/
│   └── deployment-plan.md
├── infra/
│   ├── README.md
│   ├── mcp-aca-main.bicep
│   └── modules/
├── platform/
│   ├── HANDOFF.md
│   ├── SECURITY-HARDENING-TODO.md
│   ├── VM-RUNBOOK-IMPLEMENTATION-PLAN.md
│   ├── azure/
│   │   ├── README.md
│   │   ├── azure.yaml
│   │   ├── config/
│   │   ├── infra/
│   │   ├── scripts/
│   │   └── oauth-routing-postmortem.md
│   └── runbooks/
└── docs/
    └── terraform-import/
        ├── EXPORTED-ARCHITECTURE.md
        └── exported-resources.json
```

## Target tree

The target follows the AVM solution-development model: check for a suitable
pattern first, then compose the solution from published AVM resource modules.
Repository-owned modules are application and platform compositions, not wrappers
that merely rename one AVM resource module.

```text
.
├── terraform/
│   ├── README.md
│   ├── modules/
│   │   ├── platform/
│   │   ├── platform-services/
│   │   ├── application-landing-zone/
│   │   ├── connectivity/
│   │   ├── network-security/
│   │   ├── private-dns-zone/
│   │   ├── private-vm/
│   │   ├── managed-identities/
│   │   └── postgresql/
│   │
│   │       # Current deployed compositions. Cloudflare and Keycloak provider
│   │       # resources remain future integrations, not current Terraform state.
│   │
│   └── env/
│       └── dev/
│           # Current thin root: configuration and deployment-specific values.
│           # Reusable composition source remains in the sibling modules/.
│           ├── README.md
│           ├── versions.tf
│           ├── providers.tf
│           ├── main.tf
│           ├── variables.tf
│           └── terraform.tfvars.example
│
├── ansible/
│   ├── README.md
│   ├── ansible.cfg
│   ├── requirements.yml
│   ├── site.yml
│   ├── inventory/
│   │   ├── README.md
│   │   ├── generated/
│   │   │   └── platform.yml
│   │   └── group_vars/
│   │       ├── all/
│   │       ├── edge.yml
│   │       ├── etcd.yml
│   │       ├── openbao.yml
│   │       ├── apps.yml
│   │       └── keycloak.yml
│   ├── roles/
│   │   ├── common/
│   │   ├── edge/
│   │   ├── etcd/
│   │   ├── openbao/
│   │   ├── apps/
│   │   └── keycloak/
│   ├── playbooks/
│   │   ├── bootstrap.yml
│   │   ├── configure-platform.yml
│   │   └── verify-platform.yml
│   └── molecule/
│       └── platform/
│
├── platform/
│   ├── azure/                 # Existing Bicep and runtime reference
│   └── runbooks/              # Existing material, not required by new path
│
├── docs/
│   ├── terraform-import/
│   │   ├── EXPORTED-ARCHITECTURE.md
│   │   └── exported-resources.json
│   └── operations/
│       ├── terraform-platform.md
│       └── ansible-platform.md
│
└── scripts/
    └── platform/
        ├── generate-ansible-inventory.sh
        └── verify-platform.sh
```

## Composition model

The filesystem layout and the module dependency graph are separate concerns.
`terraform/env/dev/` is only a thin root module. It does not contain copies of
the platform, infrastructure, data, or application modules; it instantiates
the reusable modules from the sibling `terraform/modules/` directory.

The composition hierarchy is intentionally shallow:

```text
env/dev
└── calls module.platform from ../modules/platform
    ├── module.foundation
    │   ├── AVM hub-and-spoke connectivity pattern
    │   └── published AVM resource modules for workload/platform spokes
    ├── module.data
    │   └── published AVM resource modules
    ├── module.infrastructure
    │   ├── app-host
    │   ├── edge
    │   ├── etcd
    │   ├── openbao
    │   └── keycloak
    │       └── published AVM compute and identity modules
    └── module.apps
        ├── registry
        ├── auth-server
        └── mcp-gateway
```

The corresponding source locations are:

```text
terraform/
├── env/
│   └── dev/                 # one root module; configuration only
└── modules/                 # reusable composition source; not under env/dev
    ├── platform/
    ├── foundation/
    ├── data/
    ├── infrastructure/
    ├── apps/
    └── integrations/
```

This reflects the current platform layout: the application host runs the three
immutable application images through Compose; the edge host runs APISIX and
Cloudflare Tunnel; etcd provides private coordination; OpenBao provides
secrets and Raft-backed state; and Keycloak is a separate identity boundary
backed by PostgreSQL. The optional ACA material remains a rollback or alternate
application deployment path, not a second environment.

Keycloak and OpenBao are generic platform infrastructure, alongside edge
routing and etcd coordination. They are shared control-plane capabilities
consumed by many SaaS applications, not application workloads themselves.
Registry, auth-server, and MCP gateway are distinct SaaS applications that
happen to share the current application VM. Their images, configuration, secret
scopes, health checks, and release lifecycles remain separate. Additional
applications become sibling compositions under `modules/apps/`, not new
environment roots.

## AVM landing-zone pattern lessons

For composition design, use these published AVM patterns as learning references:

- [ALZ Terraform Module](https://registry.terraform.io/modules/Azure/avm-ptn-alz/azurerm/latest)
- [ALZ Connectivity Hub and Spoke VNet](https://registry.terraform.io/modules/Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm/latest)

The patterns demonstrate the shape we want without making this platform an ALZ
deployment:

- A pattern module composes many resource modules into a capability; it does not
  expose one repository wrapper per Azure resource.
- Related resources are supplied through structured maps and objects, allowing
  one composition to create multiple instances.
- `enabled_resources`-style switches keep optional capability choices in the
  composition contract instead of multiplying environment roots.
- Naming conventions, shared settings, and outputs are defined at the
  composition boundary.
- Submodules represent meaningful capability boundaries such as connectivity,
  supporting services, or a workload, not individual resources.

Applied here, `foundation`, `data`, `infrastructure/*`, and `apps/*` should follow that same shape.
They should consume AVM resource modules directly, expose only platform-level
inputs and outputs, and allow the single `env/dev` root to select capabilities
with small maps or objects. The ALZ patterns are our architectural guidelines:
we should adopt their proven composition, naming, dependency, security, and
capability-boundary practices by default, then deliberately simplify only
where the disposable test bench has a documented scope difference. A smaller
environment is not a reason to abandon the pattern; it is a reason to provide
smaller inputs and disable unneeded capabilities.

The connectivity pattern is the network boundary for the future business
platform: a shared hub, an ingress/platform-services spoke containing the
Cloudflare Tunnel and APISIX domain, and workload spokes added as applications
need independent network boundaries. The initial dev deployment may contain
only one workload spoke, but the module contract should not encode a
permanently flat single-VNet assumption.

## Ownership boundaries

| Directory | Owner | Responsibility |
|---|---|---|
| `terraform/env/dev/` | Terraform | The single thin development environment instantiation, provider/backend configuration, and deployment-specific values. |
| `terraform/modules/platform/` | Terraform | Top-level composition of the SaaS platform, shared infrastructure, and application workloads. |
| `terraform/modules/foundation/` | Terraform + AVM | Composition of shared network, access, identity, and connectivity resources. |
| `terraform/modules/data/` | Terraform + AVM | Composition of shared data, secrets, registry, database, and private-link resources. |
| `terraform/modules/infrastructure/` | Terraform + AVM | Generic shared infrastructure such as the application host, edge, etcd, OpenBao, and Keycloak. |
| `terraform/modules/apps/` | Terraform + Ansible | Distinct containerized SaaS applications and their deployment contracts, not handwritten replacements for AVM resources. |
| `terraform/modules/integrations/` | Cloudflare/Keycloak providers | External control-plane integrations with explicit lifecycle boundaries. |
| `ansible/roles/` | Ansible | VM-local packages, files, services, certificates, and health checks. |
| `ansible/inventory/generated/` | Terraform output | Non-secret VM addresses, host groups, and connection metadata. |
| `platform/azure/` | Bicep, temporary reference | Existing canonical deployment and runtime material. |
| `platform/runbooks/` | Existing runbook material | Not part of the initial pure-Ansible execution path. |
| `docs/terraform-import/` | Documentation | Canonical resource inventory and dependency model. |

## Deliberate exclusions

- No repository wrapper module whose only purpose is to rename one AVM module.
- No handwritten Azure resource when a suitable published AVM resource module exists.
- Prefer a published AVM pattern where it matches; otherwise compose the
  platform from published AVM resource modules using the same pattern
  conventions.
- No secret values in `terraform.tfvars`, cloud-init, generated inventory, or
  ordinary Terraform outputs.
- No sibling NIC or extension modules for resources owned by the AVM VM module.
- No Terraform provisioners for normal Ansible execution.
- No new Terraform implementation under the existing Bicep directory.
- No Azure Automation dependency for the initial deployment and operations path.
- Keycloak provider resources run only after Ansible has bootstrapped and verified
  the Keycloak service.
