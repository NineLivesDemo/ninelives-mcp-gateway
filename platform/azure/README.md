# Azure platform foundation

This directory is a relocatable Azure Developer CLI and Bicep project for the shared platform foundation. It is intentionally separate from the Registry-specific templates under the repository-root `infra/` directory.

The current stage provisions the foundation boundary and role-specific runtime contracts: dedicated resource groups, the private VNet and subnets, NAT egress, private DNS, the platform Key Vault and auto-unseal key, the Automation Account, private base VMs, and the pinned etcd, OpenBao, and edge Compose/systemd artifacts. It does not provision Cloudflare account objects, DNS records, ACA applications, runtime secrets, OpenBao initialization, or service enablement.

No secret values belong in this directory. The Bicep parameters contain only deployment metadata and the administrator's public SSH key. Runtime values are added through the approved Key Vault and OpenBao workflows after the infrastructure is provisioned.

## Layout

```text
platform/azure/
├── azure.yaml
├── infra/
│   ├── main.bicep
│   ├── main.bicepparam
│   └── modules/
│       ├── aca-app.bicep
│       ├── aca-apps.bicep
│       ├── aca-environment.bicep
│       ├── acr-pull-role.bicep
│       ├── application-vm.bicep
│       ├── edge-vm.bicep
│       ├── etcd-vm.bicep
│       ├── key-vault-secret-role.bicep
│       ├── keycloak-vm.bicep
│       ├── linux-vm.bicep
│       ├── network.bicep
│       ├── openbao-vm.bicep
│       ├── ops.bicep
│       ├── postgresql-private-endpoint.bicep
│       └── private-dns.bicep
├── config/
│   ├── apps/
│   ├── edge/
│   ├── etcd/
│   ├── keycloak/
│   ├── openbao/
│   ├── secrets/
│   └── tls/
├── scripts/
└── README.md
```

## Current deployment boundary

- Subscription: `24595c03-870c-4a3e-93b3-51ec93c246bf`
- Region: `westus3`
- Environment: `platform-pilot`
- VNet: `10.60.0.0/16`
- VM private addresses: edge `10.60.1.4`, etcd `10.60.2.4`, OpenBao `10.60.3.4`
- Registry application VM private address: `10.60.4.4` in `rg-mcp-registry`
- Keycloak VM private address: `10.60.5.4` in `rg-mcp-keycloak`
- VM sizes: edge, etcd, and OpenBao use `Standard_D2ls_v7`; the Registry and
  Keycloak application VMs use `Standard_E2ds_v7`
- Ubuntu 24.04 Marketplace image is explicitly pinned in `modules/linux-vm.bicep`
- No VM public IPs
- Shared NAT Gateway for deterministic outbound traffic

## Break-glass VM access

Set `deployBastion = true` to deploy Azure Bastion Standard in the dedicated
`AzureBastionSubnet`. Bastion provides native SSH tunneling over the Azure
control plane while keeping every platform VM private and without depending on
the operator's Mullvad routing. The Bastion public IP is a managed access
endpoint; it is not assigned to any VM.

After deployment, an operator or agent can connect with the existing VM SSH key:

```bash
az extension add --name ssh

BASTION_NAME='bas-vnet-platform-pilot'
BASTION_RESOURCE_GROUP='rg-network'
VM_ID="$(az vm show \
  --resource-group rg-mcp-registry \
  --name vm-platform-apps \
  --query id \
  --output tsv)"

az network bastion ssh \
  --name "$BASTION_NAME" \
  --resource-group "$BASTION_RESOURCE_GROUP" \
  --target-resource-id "$VM_ID" \
  --auth-type ssh-key \
  --username platformadmin \
  --ssh-key "$HOME/.ssh/id_ed25519"
```

Use `az network bastion tunnel` when a local TCP listener is needed for a
separate SSH client or an automated agent. Keep the VM administrator private key
outside the repository. Azure VM Run Command remains the fallback when an SSH
client is unavailable.

## Runtime slices

- `config/etcd/` contains the private mTLS etcd runtime.
- `config/openbao/` contains the Raft and Azure Key Vault auto-unseal runtime.
- `config/edge/` contains APISIX, the existing Cloudflare Tunnel connector, and the guarded ACA Registry route renderer.

The edge connector uses the existing Cloudflare tunnel `mcp-gateway-registry-edge`. Cloudflare account discovery and tunnel-token retrieval are operator actions; the account API token is never embedded in Bicep, cloud-init, or the VM runtime. Account-owned API tokens must use account-scoped Cloudflare API endpoints.

The application tier is conditional and remains disabled by default with `deployApps = false`. When explicitly enabled, it creates a private ACA environment on `snet-aca`, deploys Registry/auth-server/MCP gateway/Keycloak, grants each app pull access to the existing ACR, and grants access only to the Key Vault secrets declared for that app. The deployment output `registryOriginHost` is the private hostname to place in the edge origin configuration.

The VM-hosted application tier is gated by `deployAppVm = false` and
`deployKeycloakVm = false`. When enabled, it creates `vm-platform-apps` in
`rg-mcp-registry` on `snet-apps` at `10.60.4.4`, running only Registry,
auth-server, and the MCP gateway through Compose. It also creates
`vm-platform-keycloak` in `rg-mcp-keycloak` on `snet-keycloak` at `10.60.5.4`,
running the official Keycloak image pinned by digest against the existing
PostgreSQL database. Keycloak and Registry are separate VM failure and access
boundaries; stdio MCP servers are not hosted by either VM. The Keycloak Compose
configuration uses the full canonical HTTPS URL for `KC_HOSTNAME` so internal
authorization-code exchanges also receive the public HTTPS issuer.

The existing Keycloak PostgreSQL server is referenced, not recreated. Set `deployKeycloakDbPrivateEndpoint = true` with its server name and resource group to create a private endpoint in `snet-private-endpoints` and link the VNet to `privatelink.postgres.database.azure.com`. The database hostname remains unchanged for application clients.

VM secret access is separately gated by `deployRuntimeAccess = false`. Enable it only after the named platform Key Vault secrets have been seeded; it grants each VM identity access at the individual secret scope rather than at the whole-vault scope.

`infra/main.apps.example.bicepparam` is a non-deployable application-tier
template populated with the previously inventoried `rg-ai-access` dependency
names. Replace every `YOUR_*` value only after the Keycloak hostname,
immutable ACR image digests, and application secret ownership are approved.

## Runtime enablement order

After the platform Key Vault has been seeded and the VM secret-sync identity
has been granted its individual secret scopes, enable services in this order:

```bash
sudo systemctl enable --now platform-secret-sync.timer
sudo systemctl start platform-secret-sync.service
sudo systemctl enable --now platform-etcd.service
sudo systemctl enable --now platform-openbao.service
sudo systemctl enable --now platform-edge-env.service
sudo systemctl enable --now platform-edge.service
```

The etcd and OpenBao units require a successful secret-sync run. The edge
environment renderer and edge service have the same dependency through their
systemd requirements. Do not enable runtime services before protected
certificates, keys, and tokens have been seeded.

## Application post-deployment initialization

For a new deployment, deploying the application tier starts Keycloak and creates
the `master` realm, but it does not initialize the application realm. After
Keycloak is reachable through its public hostname, run the repository bootstrap
once:

```bash
tmp_script="$(mktemp)"
trap 'rm -f "$tmp_script"; unset KEYCLOAK_ADMIN_URL KEYCLOAK_ADMIN KEYCLOAK_ADMIN_PASSWORD INITIAL_ADMIN_PASSWORD AUTH_SERVER_EXTERNAL_URL REGISTRY_URL' EXIT
cp keycloak/setup/init-keycloak.sh "$tmp_script"

export KEYCLOAK_ADMIN_URL="https://keycloak.example.com"
export KEYCLOAK_ADMIN="admin"
export KEYCLOAK_ADMIN_PASSWORD="$(az keyvault secret show \
  --vault-name "$APPLICATION_KEY_VAULT_NAME" \
  --name "keycloak-admin-password" \
  --query value -o tsv)"
export INITIAL_ADMIN_PASSWORD="$KEYCLOAK_ADMIN_PASSWORD"
export AUTH_SERVER_EXTERNAL_URL="https://registry.example.com"
export REGISTRY_URL="https://registry.example.com"

bash "$tmp_script"
```

Run this from an operator workstation with `az` authenticated to the application Key Vault. The temporary copy prevents the bootstrap script from loading a local `.env`; secrets are passed through the environment and must not be placed in command arguments or logs. The script creates the `mcp-gateway` realm, web and M2M clients, groups, scopes, mappers, and initial realm administrator. Run it only for initial provisioning or after reviewing its effects: rerunning it can regenerate client secrets. Replace the example hostname with the deployed Keycloak hostname.

For the current `platform-pilot` deployment, the persisted `mcp-gateway` realm
already exists and has been verified. Do not rerun this script; use the
read-only Keycloak checks and repair only the specific drift that is found.

## Read-only preview

From this directory, after setting the administrator public key in the environment:

```bash
export AZURE_ADMIN_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
az deployment sub what-if \
  --location westus3 \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

Do not run a deployment until the generated Bicep has passed validation and the resource-group, identity, image, disk, quota, secret-RBAC, and ACA-origin assumptions have been reviewed. Runtime services remain disabled until their protected inputs are seeded.
## Guarded WSL deployment

Run the deployment wrapper from WSL. It always validates and runs a non-mutating `what-if` first. It never deploys unless both `--apply` and the exact `--confirm DEPLOY` flag are supplied:

```bash
export AZURE_ADMIN_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
./platform/azure/scripts/deploy-platform.sh
./platform/azure/scripts/deploy-platform.sh --apply --confirm DEPLOY
```

Use a different `.bicepparam` file with `--parameters` when promoting a specific environment. The wrapper does not accept secrets on the command line and does not create resources when run without `--apply`.
## Test-bench Hybrid Worker Python compatibility

The available Linux Hybrid Worker handler currently expects an executable named `Python` and imports the removed `imp` module. Ubuntu 24.04 provides Python 3.12 and no Python 3.10 package. For the test bench only, install the pinned self-contained CPython runtime without replacing system Python:

```bash
sudo bash platform/azure/scripts/bootstrap/install-python310-compat.sh
```

The installer installs UV under `/opt/platform/uv`, uses `uv python install 3.10` to manage the runtime under `/opt/platform/python310`, and creates `/usr/local/bin/Python` pointing to the managed Python 3.10 interpreter. It does not change `/usr/bin/python3`. This compatibility path is x86_64-only and should not be treated as the production Hybrid Worker support strategy.
