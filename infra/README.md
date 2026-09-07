# Registry Azure infrastructure

This directory owns the MCP Gateway Registry Azure deployment. It is independent of the Neo4j infrastructure in `/home/rpl/Projects/NLAI/azd-neo4j`; the two workloads do not share a VM, managed identity, storage path, or Bicep entrypoint.

## ACA target

`mcp-aca-main.bicep` creates a new private workload-profile Azure Container Apps environment on a dedicated delegated subnet, a NAT Gateway with a static egress IP, and separate Container Apps for:

- the Registry;
- the auth-server;
- the MCP gateway;
- Keycloak; and
- APISIX;
- etcd; and
- cloudflared.

Each app receives its own user-assigned managed identity with only ACR pull and the Key Vault secret-read access required by that app. All application ingress is private; Cloudflare Tunnel reaches APISIX, and APISIX routes to the application services. The current Bicep entrypoint still needs the APISIX/etcd edge modules added before deployment.

The example parameter file intentionally contains placeholders:

```bash
az bicep build --file infra/mcp-aca-main.bicep --stdout >/dev/null
az deployment group what-if \
  --resource-group rg-ai-access \
  --template-file infra/mcp-aca-main.bicep \
  --parameters infra/mcp-aca.example.bicepparam
```

Do not run a deployment until image digests, Key Vault secret names, PostgreSQL connectivity, subnet availability, ACA quota, and Cloudflare private origin routing have been reviewed and approved. Do not pass secret values as Bicep parameters.

The Cloudflare tunnel's origin configuration is external to Bicep. The intended target is the private APISIX app; APISIX then routes to `http://mcp-registry:80` and `http://keycloak:80` inside the ACA environment. These routes must be validated in a canary.
