# Azure Deployment Plan: Registry ACA-First; Neo4j Separate

Current selected path: deploy the MCP Gateway Registry as an independent, container-first Azure Container Apps workload. The Registry does not share a VM, network identity, storage, or lifecycle with Neo4j. Neo4j remains owned by the separate `azd-neo4j` project.

Status: Draft; selected ingress architecture; APISIX/etcd IaC extension pending; not approved or deployed

Decision precedence: sections 1-16 describe the active Registry target. Sections 17-22 are retained as historical VM research and fallback context only. No Azure resource mutation, image mirror, or deployment is approved by this document.

## 1. Scope and non-goals

- Target for the initial canary: a new private workload-profile ACA environment with a dedicated delegated subnet, deterministic NAT egress, and separate Container Apps for the Registry services.
- Runtime profile: Registry, auth-server, MCP gateway, Keycloak, APISIX, etcd, and cloudflared run as independent containers. MongoDB Atlas and the existing PostgreSQL server remain external dependencies; OpenBao and bundled Prometheus/Grafana remain local/debug-only services.
- Objective: a cost-conscious single-region development and experimental deployment for fewer than 1,000 users. This is not a production high-availability design.
- Subscription: Azure subscription 1 (`24595c03-870c-4a3e-93b3-51ec93c246bf`).
- Region and resource group: `westus3`, `rg-ai-access`.
- Retained: Keycloak, the registry auth-server, the MCP gateway, MongoDB-compatible storage, LiteLLM/Voyage embeddings, and the registry's A2A registration/discovery surface.
- Deferred: standalone A2A runtime containers, OpenBao egress authentication, AWS-only integrations, PingFederate, the standalone metrics service, bundled Prometheus/Grafana, and demo MCP server containers.
- No Neo4j resource, VM, VM identity, VM disk, or shared Compose host is included in this Registry baseline. APISIX and etcd initially run as private containers; a dedicated edge VM is a later relocation option. APIM, Front Door, WAF, private endpoints, and multi-region design remain later hardening or scale decisions.

The later VM topology, configuration mapping, evidence register, blocker list, and cost estimate remain in this file as preserved research/fallback material. They must not be read as approval to reuse Neo4j infrastructure for the Registry.

Cloudflare Tunnel provides the browser-facing HTTPS endpoints and routes only to private APISIX ingress. APISIX routes to the Registry and other private ACA app-name targets. No application or etcd ingress is public. A custom domain and managed certificate remain Cloudflare concerns, while Keycloak administration is exposed only through the controlled tunnel bootstrap route.

## 2. Verified local baseline

| Surface | Observed behavior | Repository evidence |
|---|---|---|
| Registry | `with-gateway` and `full` mode; NGINX, UI, FastAPI registry, MCP proxy, OAuth callback proxy, and A2A discovery are in one image. | `.env.default:5-13`; `docker-compose.prebuilt.yml:48-371`; `docker/Dockerfile.registry:123-171` |
| Auth server | Separate process on container port `8888`; local traffic reaches it through the registry gateway. | `docker-compose.prebuilt.yml:381-535`; `docker/auth-entrypoint.sh:122-140` |
| MCP gateway | Separate process on container port `8003`; it calls the registry and is reached through the gateway. | `docker-compose.prebuilt.yml:542-581`; `servers/mcpgw/server.py:195-198` |
| Keycloak | Keycloak on container port `8080`; the local setup script calls `KEYCLOAK_ADMIN_URL` directly. | `.env.default:15-35`; `docker-compose.prebuilt.yml:648-706`; `keycloak/setup/init-keycloak.sh:800-824` |
| Storage | `STORAGE_BACKEND=mongodb-ce`; a full `MONGODB_CONNECTION_STRING` overrides discrete `DOCUMENTDB_*` settings. | `.env.default:37-46`; `registry/core/config.py:1333-1344,1589-1606`; `docs/faq/configuring-mongodb-atlas-backend.md:1-33` |
| Search | The search collection name includes the configured embedding dimension and startup creates its index. | `registry/repositories/documentdb/search_repository.py:646-662,753-802` |
| Product telemetry | Product telemetry is disabled with `MCP_TELEMETRY_DISABLED=1`; this is separate from optional application metrics. | `.env.default:73-74`; `docker-compose.prebuilt.yml:307-318` |
| Embeddings | LiteLLM/Voyage with model `voyage/voyage-3`, dimension `1024`, and an HTTPS API base. | `.env.default:61-71` |
| Local preparation | `build_and_run.sh --prebuilt` copies local seed files, generates local secrets, pulls images, and starts Compose; those host-side actions are not an ACA startup contract. | `build_and_run.sh:214-339,341-402,439-465` |

The standalone demo MCP containers are absent from the prebuilt Compose profile. The built-in `airegistry-tools` record is different: it is registered by the registry process at startup unless `DISABLE_AI_REGISTRY_TOOLS_SERVER=true`. It does not require a separate container. (`registry/main.py:783-793`; `registry/services/demo_servers_init.py:45-105,139-156`)

Observed runtime confirmation on 2026-08-31: `docker compose down` removed the registry, auth-server, MCP gateway, Keycloak, Keycloak PostgreSQL, MongoDB, MongoDB initialization/keyfile helpers, OpenBao, Prometheus, Grafana, and the default Compose network. This confirms the local container topology, but the removal output alone does not establish health or readiness.

Operator verification update on 2026-08-31: the user reports that the local stack, including their source-code modifications, was manually exercised and behaved as expected. This supplies operator-confirmed evidence for the normal functional path, including the behaviors previously listed as unproven. It is not an independently replayed automated test result, so the remaining local work is focused on combined Neo4j/registry resource measurements, backup and recovery, and Azure-facing security behavior rather than repeating the basic functional walkthrough.

## 3. Baseline topology

```text
Public Internet
  |
  | Cloudflare DNS, TLS, WAF, Access
  v
Container App: cloudflared
  |-- outbound tunnel connection; no ACA ingress
  |-- private ACA HTTP --> apisix (target port 9080)

Container App: apisix
  |-- internal ingress only, target port 9080
  |-- etcd-backed routes and Dashboard/Admin API
  |-- private ACA HTTP --> mcp-registry, auth-server, mcpgw-server, keycloak

Container App: etcd
  |-- internal client/peer ports only
  |-- durable storage required for route configuration

Container App: mcp-registry
  |-- internal ingress only, target port 8080
  |-- NGINX/UI/API/MCP proxy/A2A discovery edge
  |-- internal ACA HTTP --> auth-server (target port 8888)
  |-- internal ACA HTTP --> mcpgw-server (target port 8003)
  |-- internal ACA HTTP --> keycloak (target port 8080)
  |-- TLS --> MongoDB Atlas
  |-- HTTPS --> LiteLLM/Voyage endpoint
  |-- managed identity --> Azure Key Vault
  |
  +--> optional Alloy sidecar: scrape localhost:9464 and forward to Grafana Cloud

Container App: auth-server
  |-- internal ingress, target port 8888
  |-- internal HTTP --> keycloak
  |-- TLS --> MongoDB Atlas when required by the auth path
  +--> optional Alloy sidecar: scrape localhost:9464 and forward to Grafana Cloud

Container App: mcpgw-server
  |-- internal ingress, target port 8003
  |-- internal HTTP --> mcp-registry
  +--> optional Alloy sidecar: scrape localhost:9464 and forward to Grafana Cloud

Container App: keycloak
  |-- internal ingress only, target port 8080
  +--> TLS --> existing PostgreSQL Flexible Server

Existing or external services
  |-- ACA environment: cae-mcp-private (new, private workload-profile environment)
  |-- ACA subnet: snet-mcp-aca (new delegated subnet)
  |-- NAT Gateway and static egress IP (new)
  |-- ACR: cr4bqvj62ztmxmi.azurecr.io
  |-- Key Vault: kv-ai-access
  |-- Application Insights: appi-litellm-4bqvj62ztmxmi
  |-- Log Analytics: log-litellm-4bqvj62ztmxmi
  |-- PostgreSQL: psql-litellm-4bqvj62ztmxmi
  |-- MongoDB Atlas: external managed service
  |-- Grafana Cloud: external managed observability service
```

APISIX is the application edge. Keycloak is a second browser-facing HTTPS application in this development baseline because `KEYCLOAK_EXTERNAL_URL` is used for browser authorization and `KEYCLOAK_ADMIN_URL` is used by `init-keycloak.sh`; APISIX owns both routes. This is an explicit exposure decision, not an assertion that public Keycloak administration is appropriate for production.

ACA service discovery uses app names or internal FQDNs for apps in the same environment. The ACA ingress endpoint is normally reached on port 80 while the app's target port remains its container port. The registry NGINX generator defaults an unqualified `AUTH_SERVER_URL` to port `8888` and an unqualified `KEYCLOAK_URL` to port `8080` (`registry/core/nginx_service.py:1283-1308,1169-1205`), so the Azure values should explicitly use `http://auth-server:80`, `http://mcpgw-server:80`, and `http://keycloak:80` unless a canary proves an alternate mapping works.

The baseline therefore uses HTTPS for every browser-facing URL and for Atlas/PostgreSQL connections. It does not claim end-to-end TLS between ACA apps; the internal app-name routes are HTTP in this parity profile. If internal encryption is a requirement, that is a separate design and validation item.

## 4. Configuration translation

The values below use placeholders intentionally. The actual ACA FQDNs must be read after app creation and must not be guessed.

| Local setting | Azure baseline |
|---|---|
| `REGISTRY_URL=http://localhost` | `https://<mcp-registry-fqdn>` |
| `REGISTRY_BASE_URL=http://registry:8080` (mcpgw) | `http://mcp-registry:80` for the ACA internal registry route |
| `AUTH_SERVER_URL=http://auth-server:8888` | `http://auth-server:80` for the ACA internal ingress route |
| `AUTH_SERVER_EXTERNAL_URL=http://localhost:8888` | `https://<mcp-registry-fqdn>`; the registry NGINX callback route forwards to the internal auth-server |
| `KEYCLOAK_URL=http://keycloak:8080` | `http://keycloak:80` for the ACA internal ingress route |
| `KEYCLOAK_EXTERNAL_URL=http://localhost:8080` | `https://<keycloak-fqdn>` for browser redirects and the Keycloak issuer |
| `KEYCLOAK_ADMIN_URL=http://localhost:8080` | `https://<keycloak-fqdn>` for the operator bootstrap step |
| `MCP_HTTPS_REQUIRED=false` | `true`; the canonical MCP resource is externally HTTPS |
| `SESSION_COOKIE_SECURE=false` | `true`; the browser-facing registry is HTTPS |
| `AUTH_PROVIDER=keycloak` / `KEYCLOAK_ENABLED=true` | Preserve; Entra substitution is not part of the parity deployment |
| `STORAGE_BACKEND=mongodb-ce` | Preserve the accepted alias and set `MONGODB_CONNECTION_STRING` to the Atlas URI |
| `DOCUMENTDB_USE_TLS=false` | Do not rely on this flag when the URI override is set; express TLS, retry, and replica options in the Atlas URI |
| `EGRESS_AUTH_ENABLED=false` | Preserve; do not deploy OpenBao for this profile |
| `SECRET_STORE_BACKEND=openbao` | Do not pass the local OpenBao settings to the Azure runtime; Azure Key Vault is the deployment secret store |
| `MCP_TELEMETRY_DISABLED=1` | Preserve product-telemetry opt-out; do not interpret it as disabling the selected metrics collection |
| `EMBEDDINGS_API_BASE` | Reuse only after an HTTPS reachability and ownership check for the existing LiteLLM endpoint |
| `EMBEDDINGS_API_KEY` | Key Vault secret reference; never place the value in Bicep, AZD, image layers, or command-line arguments |
| Local Compose bind mounts | No Azure Files in the baseline; see persistence decision below |

The registry and auth-server must receive the same `SECRET_KEY` and `AUTH_SERVER_NGINX_MARKER_SECRET` values across all replicas. Client secrets are generated by Keycloak and must be placed into runtime secret storage after bootstrap; `get-all-client-credentials.sh` writes them under `.oauth-tokens` and does not update `.env`.

## 5. Reused Azure resources

| Resource | Existing resource | Planned use |
|---|---|---|
| Resource group | `rg-ai-access` | Container Apps and deployment metadata |
| Container Apps environment | `cae-mcp-private` (new) | Private host for the seven Registry-side apps |
| VNet/subnet | Existing VNet plus new `snet-mcp-aca` | Dedicated delegated ACA infrastructure subnet |
| NAT Gateway/static IP | `nat-mcp-aca-egress` / `pip-mcp-aca-egress` (new) | Deterministic Atlas and hosted-service egress |
| Container Registry | `cr4bqvj62ztmxmi` (`Standard`) | Store mirrored, pinned registry/auth/mcpgw images |
| Key Vault | `kv-ai-access` with RBAC enabled | Runtime secrets and credentials |
| Application Insights | `appi-litellm-4bqvj62ztmxmi` | Existing monitoring resource, if the environment is configured to use it |
| Log Analytics | `log-litellm-4bqvj62ztmxmi` | Existing ACA Azure Monitor destination |
| PostgreSQL Flexible Server | `psql-litellm-4bqvj62ztmxmi` | Dedicated Keycloak database and login |
| MongoDB Atlas | Existing external service | Application state, search, scopes, servers, agents, and scans |
| Grafana Cloud | Existing external service | Optional application metrics destination |

Application data does not require Azure Files in the selected MongoDB profile. The initial ACA etcd deployment is different: it requires a durable data path, so an Azure Files share or an external etcd service must be selected and validated before the APISIX/etcd modules are deployable. This persistence decision does not apply to the Registry application containers.

## 6. Azure resources and identities

- Create a new private workload-profile `Microsoft.App/managedEnvironments` resource on a dedicated delegated subnet, rather than modifying the existing ACA environment.
- Create seven `Microsoft.App/containerApps` resources: `mcp-registry`, `auth-server`, `mcpgw-server`, `keycloak`, `apisix`, `etcd`, and `cloudflared`.
- Give each app a separate user-assigned managed identity. Grant only the ACR pull permission and the Key Vault secret-read permission needed by that app; do not grant broad contributor access.
- Create a dedicated PostgreSQL database and login for Keycloak through an explicit post-provisioning database operation. Validate the server's TLS and firewall policy before use.
- Do not create a VM, VM NIC/NSG, private endpoint, or ACA Job in the initial baseline. APISIX and etcd require an explicit private ACA deployment and durable etcd storage; the dedicated edge VM remains a later relocation option. The NAT Gateway and static egress IP are intentional dependencies of the private ACA subnet.
- The current realm/client bootstrap remains an operator step. A temporary bootstrap job is a possible hardening option, but it is not source-verified as an equivalent replacement for the script and is therefore not assumed.

## 7. Image, secret, and infrastructure handling

- Use Bicep directly, optionally orchestrated by AZD only if the generated project remains transparent. Do not generate infrastructure or mutate Azure resources until this plan is approved.
- Mirror the exact prebuilt registry, auth-server, and mcpgw image references into ACR only after confirming image names, tags, architecture, exposed ports, and provenance. Deploy immutable tags or digests, never an unpinned `latest`.
- Use ACA secret references backed by Key Vault where supported by the chosen deployment schema. Secrets include `SECRET_KEY`, `AUTH_SERVER_NGINX_MARKER_SECRET`, Keycloak admin/database credentials, the Atlas URI, embeddings credentials, and generated Keycloak client secrets.
- Do not place secret values in Bicep parameters, `azure.yaml`, source files, image layers, shell arguments, or CI logs. The live-looking embeddings value in `.env.default` must be replaced with a placeholder and rotated if it is genuine.
- Keep local Compose initialization jobs and host bind mounts out of the runtime image. Use `scripts/init-mongodb-ce.py` as an explicit Atlas initialization step; it supports `MONGODB_CONNECTION_STRING`, skips local replica-set initialization, and seeds default scopes/indexes.

## 8. Persistence and initialization

MongoDB is authoritative for the selected profile. The server and agent repositories persist records and enabled/disabled state there; search initialization creates the dimension-specific collection and index at application startup. `server_state.json` and `agent_state.json` are legacy/file-backend paths, not a reason to mount Azure Files for this deployment.

The Atlas initialization sequence is:

1. Create or select the Atlas database and TLS connection string.
2. Configure Atlas Network Access for the ACA application's actual outbound source addresses.
3. Run `scripts/init-mongodb-ce.py` with `MONGODB_CONNECTION_STRING` and verify collections, indexes, and default scopes.
4. Start the registry and confirm its configured embedding dimension creates the expected search collection/index.
5. Register non-built-in MCP/A2A assets through the application API or a deliberate, separately reviewed seed process.

The initializer does not register arbitrary MCP servers or A2A agents. The registry's built-in `airegistry-tools` record is created by application startup unless disabled.

## 9. HTTPS, Keycloak, and authentication

- Set `MCP_HTTPS_REQUIRED=true` and `SESSION_COOKIE_SECURE=true`.
- Run Keycloak in normal production `start` mode, not `start-dev`.
- Configure Keycloak's public hostname and trusted proxy headers according to the current Keycloak reverse-proxy/hostname documentation. Do not copy the local `KC_PROXY=edge` setting without validating the Keycloak version and proxy-header model.
- Keep separate internal and external URL semantics: internal URL for discovery/JWKS/token/user-info calls, external URL for browser redirects and issuer-facing metadata.
- Set `KEYCLOAK_EXTERNAL_URL` and `KEYCLOAK_ADMIN_URL` to the Cloudflare HTTPS hostname. Cloudflared routes these URLs to private Keycloak ingress; there is no direct public ACA ingress.
- Validate issuer, authorization and logout redirects, callback URLs, secure cookies, JWKS retrieval, user-info calls, and the admin bootstrap before declaring the app deployed.
- Do not substitute Entra ID in the first pass. Entra ID can replace the identity provider, but it does not replace this repository's auth-server, registry authorization policies, or MCP/A2A proxy behavior.

## 10. Observability

- Preserve `MCP_TELEMETRY_DISABLED=1` for product telemetry.
- ACA stdout/stderr remains the platform log path through the new environment's Log Analytics destination. Confirm diagnostic settings rather than assuming Application Insights receives every application signal.
- Registry, auth-server, and mcpgw source initialization exposes Prometheus-compatible metrics on port `9464` when configured. Source inspection does not prove direct OTLP push from the core prebuilt images.
- Use a separate containerized Alloy or OpenTelemetry Collector app when the hosted Grafana endpoint/authentication contract is supplied. Applications should send telemetry over private ACA service discovery; hosted-Grafana credentials must remain in the collector, not in every application container.
- Do not promise traces or full OpenTelemetry coverage from unchanged prebuilt images. The generic MCP-server image's optional `opentelemetry-instrument` wrapper does not establish equivalent instrumentation for the registry and auth entrypoints.

## 11. Quota, capacity, and network checks

- Region checked: `westus3`.
- Earlier `Microsoft.App` quota discovery returned an inconsistent `ManagedEnvironmentCount` pair: limit `1`, usage `2`, while the subscription already has two environments. This is an observed CLI result, not a capacity guarantee. The new environment must be validated against current quota and subnet requirements before deployment.
- `SessionPools` reported limit `1` and usage `0`; session pools are not used.
- Storage quota discovery exposed the `StorageAccounts` metric without a numeric limit/usage in the observed response. The etcd persistence choice must include storage quota and latency validation before deployment.
- The new subnet uses a NAT Gateway and static public IP. Atlas Network Access must allow only the verified NAT public IP; do not use `0.0.0.0/0`.
- Per-app CPU, memory, replica, ingress, probe, and workload-profile settings are unknown until the exact image manifests and environment configuration are inspected. Treat them as validation inputs, not assumptions.

## 12. Verification status and evidence register

Status labels:

- **Verified-source:** directly observed in repository code/configuration or an official product document.
- **Observed-state:** read from the current local/Azure environment; re-check before deployment.
- **Implementation choice:** an explicit baseline decision, not a product capability claim.
- **Pending-canary:** must be proven against the selected image/environment before the plan is considered deployable.

| Claim or decision | Status | Evidence |
|---|---|---|
| ACA external HTTP ingress supplies an HTTPS endpoint and internal app communication is supported within an environment. | Verified-source | [ACA ingress overview](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview); [connect apps](https://learn.microsoft.com/en-us/azure/container-apps/connect-apps) |
| ACA app-name routes and target-port behavior require a canary for this NGINX URL parser. | Verified-source + Pending-canary | [ACA connect apps](https://learn.microsoft.com/en-us/azure/container-apps/connect-apps); `registry/core/nginx_service.py:1169-1205,1283-1308` |
| ACA secrets and managed identities can be used for runtime secret/image access. | Verified-source | [ACA secrets](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets); [managed identity image pull](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull) |
| ACA sidecars share an app's container context and can be used for a local metrics scrape. | Verified-source + Pending-canary | [ACA containers](https://learn.microsoft.com/en-us/azure/container-apps/containers); `registry/observability/meters.py:44-103`; `auth_server/observability/meters.py:24-81`; `servers/mcpgw/observability_bootstrap.py:105-130` |
| The selected MongoDB profile persists application state in MongoDB and supports an Atlas URI override. | Verified-source | `registry/repositories/documentdb/*`; `registry/core/config.py:1333-1344,1589-1606`; `scripts/init-mongodb-ce.py:45-61,311-399`; [Atlas URI/network guide](https://www.mongodb.com/docs/atlas/security/ip-access-list/) |
| The app creates a dimension-specific search collection/index at startup. | Verified-source | `registry/repositories/documentdb/search_repository.py:646-662,753-802`; `registry/main.py:525-538` |
| Keycloak requires a public hostname/proxy configuration and database TLS must be validated. | Verified-source | [Keycloak hostname](https://www.keycloak.org/server/hostname); [reverse proxy](https://www.keycloak.org/server/reverseproxy); [database](https://www.keycloak.org/server/db) |
| Keycloak external exposure is the simplest parity/bootstrap path but is not a production security recommendation. | Implementation choice | `auth_server/providers/keycloak.py:47-80,467-494`; `keycloak/setup/init-keycloak.sh:22-54,800-824`; security review of the direct admin flow |
| PostgreSQL public access/firewall behavior must be checked before using the existing server. | Verified-source + Observed-state | [Azure PostgreSQL public networking](https://learn.microsoft.com/en-us/azure/postgresql/network/concepts-networking-public); existing server inventory |
| Alloy is preferred over promising direct OTLP from unchanged core images. | Implementation choice + Pending-canary | [Grafana Alloy Prometheus collection](https://grafana.com/docs/alloy/latest/collect/prometheus-metrics/); [Grafana Cloud OTLP](https://grafana.com/docs/grafana-cloud/send-data/otlp/send-data-otlp/); entrypoint/source inspection |
| Custom domains/certificates are optional after the default ACA HTTPS endpoint works. | Verified-source | [ACA custom domains and certificates](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates) |

This register intentionally separates what the repository proves, what Azure currently reports, and what must be validated with a canary. Claims not listed as verified must not be encoded as deployment assumptions.

## 13. Execution sequence

1. Approve this plan and the explicit decision to route Keycloak through the controlled Cloudflare Tunnel bootstrap path.
2. Inspect the existing VNet, address space, subnet availability, Log Analytics workspace, ACR, Key Vault, PostgreSQL server, and current ACA quota.
3. Confirm image source references, tags/digests, architecture, target ports, health endpoints, and startup behavior for all five container images.
4. Generate and statically validate the independent Registry Bicep entrypoint in `infra/mcp-aca-main.bicep`; do not invoke the Neo4j `azd-neo4j` entrypoint.
5. Validate Bicep, RBAC scopes, Key Vault references, ACA ingress, service discovery, environment variables, probes, replicas, and secret naming.
6. Create/configure the dedicated Keycloak PostgreSQL database/login and verify TLS and firewall access.
7. Confirm the NAT public IP, configure the narrowest Atlas Network Access rule, store the Atlas URI in Key Vault, and run `scripts/init-mongodb-ce.py`.
8. Mirror the confirmed images to ACR with immutable references and grant only the required pull identities.
9. Deploy a canary, then verify private cloudflared-to-ACA reachability, internal URL port translation, Keycloak hostname/proxy/issuer behavior, OAuth callbacks, secure cookies, Atlas persistence, and registry startup/index initialization.
10. Configure and canary Alloy metrics forwarding to Grafana Cloud; confirm ACA logs through Log Analytics/Application Insights configuration.
11. Run functional checks for registry health, login/logout, registry APIs, virtual MCP creation/use, MCP gateway routing, built-in registry tools, and persistence across app restarts.
12. Restrict or remove direct Keycloak administrative ingress after bootstrap where practical. Defer separate A2A runtime agents until their containers and authentication contract are tested.

## 14. Decisions and approval gates

- **Decided:** local-parity development scope, `westus3`, `rg-ai-access`, a new private ACA environment and delegated subnet, existing ACR, Key Vault, PostgreSQL server, MongoDB Atlas, and Grafana Cloud.
- **Decided:** retain Keycloak and the repository auth-server; do not substitute Entra ID in the first pass.
- **Decided:** no Azure Files baseline, because current source evidence does not establish a required persistent filesystem path for the MongoDB backend.
- **Decided:** no APIM, Front Door, Application Gateway, private endpoint, bundled Prometheus/Grafana, OpenBao, metrics-service, demo servers, or standalone A2A runtime containers.
- **Explicit trade-off:** cloudflared is containerized in ACA and relies on private app-name routing rather than a general-purpose VM or Azure L7 gateway. This requires a focused network canary.
- **Blocking prerequisites:** VNet/subnet delegation and ACA quota; NAT egress for Atlas; PostgreSQL connectivity/TLS/firewall; exact image metadata; Key Vault and ACR identity permissions; Keycloak issuer/callback/secure-cookie canary; cloudflared-to-ACA private routing canary.
- **Approval gate:** do not generate infrastructure, mirror images, alter Azure resources, or deploy until the user approves this revised, source-verified plan and the Keycloak exposure trade-off.

## 15. Blocker review — 2026-08-31

The following checks were performed against the current workspace and Azure subscription. This section records current blockers; it does not approve or deploy the plan.

| Priority | Finding | Status and required action |
|---|---|---|
| P0 | Plan status is still `Draft`. | **Blocking workflow gate.** The Azure validation workflow requires an approved plan. Approve the scope and the temporary public Keycloak exposure decision before validation or infrastructure generation. |
| P0 | `.env.default:68` contains a live-looking embeddings credential. | **Security blocker.** Revoke/rotate it if genuine, replace the file value with an unmistakable placeholder, and load the replacement only through Key Vault. Do not copy the file into Azure unchanged. |
| P0 | `kv-ai-access` does not currently list the deployment-specific secrets (`SECRET_KEY`, `AUTH_SERVER_NGINX_MARKER_SECRET`, Atlas URI, Keycloak credentials, embeddings credential, or generated client secrets). | **Secret provisioning blocker.** Create the required secrets with strong values, then bind only the necessary secrets to each Container App identity. |
| P0 | ACR `cr4bqvj62ztmxmi.azurecr.io` has no `registry`, `auth-server`, or `mcpgw` repositories; Compose defaults all three to the mutable `latest` tag. | **Image blocker.** Confirm provenance, architecture, ports, probes, and exact digests, then mirror the images to ACR and deploy immutable references. |
| P0 | ACA environment `cae-litellm-4bqvj62ztmxmi` is `Succeeded` but reports no `outboundIpAddresses` and has no VNet configuration. | **Network blocker for a narrow Atlas rule.** Obtain the actual ACA egress addresses or change the design to provide controlled egress. Do not assume the environment `staticIp` is an outbound allowlist address. |
| P0 | The Atlas URI, database access, and Atlas Network Access rule have not been provisioned for this deployment. | **Data blocker.** Store the TLS URI in Key Vault, allow only verified ACA egress, run `scripts/init-mongodb-ce.py`, and verify collections/indexes/default scopes before starting the registry. |
| P0 | PostgreSQL is `Ready`, version 16, and password authentication is enabled, but the dedicated Keycloak database/login is not verified. Its current firewall includes the broad `AllowAllAzureServicesAndResourcesWithinAzureIps` rule. | **Keycloak data/security blocker.** Create the dedicated database/login, verify TLS from ACA, and replace or explicitly accept the broad firewall rule for this development deployment. |
| P0 | Keycloak's external hostname, proxy-header mode, issuer, callback URLs, and bootstrap credentials are not configured. | **Authentication blocker.** Use `start` rather than `start-dev`, configure the tested hostname/proxy model, bootstrap the realm/clients, inject generated secrets into Key Vault, and validate browser login/logout and JWKS/token flows. |
| P1 | ACA internal URL/port behavior has not been proven for the NGINX upstreams. | **Canary blocker.** Deploy a minimal canary and prove `auth-server:80`, `mcpgw-server:80`, and `keycloak:80` routes to target ports `8888`, `8003`, and `8080`; verify that the NGINX-generated configuration preserves the intended scheme and port. |
| P1 | New app identities and their ACR/Key Vault role assignments do not yet exist. | **Provisioning blocker.** Create system-assigned identities and grant only `AcrPull` plus the required Key Vault secret-read permissions. The current signed-in principal has subscription-level `Owner`, so the operator permission prerequisite is currently satisfied. |
| P1 | Per-app CPU/memory, replicas, ingress, probes, and existing environment capacity are not yet selected or validated. | **Capacity/probe blocker.** Inspect the consumption environment and image health endpoints, then validate a canary before choosing final settings. |

The following are **not current deployment blockers** for the selected scope: custom domains, APIM/Front Door/WAF, Azure Files, bundled Prometheus/Grafana, Alloy metrics forwarding, Entra ID substitution, OpenBao, demo servers, and separate A2A runtime agents. Alloy remains a post-start observability canary, not a prerequisite for application startup.

## 16. Cost estimate — 2026-08-31

This is a USD retail-price estimate, not a quote. It uses current Azure Retail Prices API values for `westus3`, a 730-hour month, no taxes or negotiated discounts, and the four new ACA apps only. The existing ACA apps in this environment may already consume the subscription-level free grant.

Assumed development shape:

- `mcp-registry`: 1 vCPU, 2 GiB
- `auth-server`: 0.5 vCPU, 1 GiB
- `mcpgw-server`: 0.5 vCPU, 1 GiB
- `keycloak`: 0.5 vCPU, 1 GiB
- One minimum replica per app; no scale-out; no Dedicated workload profile

The current ACA Consumption meters are $0.000024 per active vCPU-second, $0.000003 per idle vCPU-second, and $0.000003 per GiB-second. At the assumed 2.5 vCPU/5 GiB allocation, ACA compute is approximately:

| Usage pattern | ACA compute/month |
|---|---:|
| Always-on replicas, mostly idle | $59 |
| Approximately 25% active time | $94 |
| Continuously active | $197 |

If Keycloak requires 1 vCPU/2 GiB instead, the corresponding figures are approximately `$71`, `$112`, and `$237`. Scaling all apps to zero can reduce idle ACA compute to near zero, but introduces cold starts and is a poor fit for a responsive identity/login path.

Other Azure costs:

| Resource | Estimated monthly cost | Treatment |
|---|---:|---|
| Existing Standard ACR | `$20.28` base, plus `$0.10/GB-month` stored | Count only if attributing the shared registry to this service; incremental image storage is small |
| Existing PostgreSQL B1ms, 32 GB | approximately `$16.09` compute/storage | Existing shared cost; adding a Keycloak database/login should have near-zero incremental compute cost |
| Key Vault | approximately `$0.03` per 10,000 Standard operations | Existing vault; normal secret reads are negligible |
| Log Analytics | `$2.30/GB` Analytics ingestion and `$0.10/GB-month` retention meter | Highly dependent on log volume and retention |
| ACA requests | `$0.40` per million after the first 2 million requests per subscription/month | Usually negligible for this development workload |
| Internet egress | Region/route dependent; current bandwidth meters are roughly `$0.05–$0.087/GB` for common Internet tiers | Usually negligible at development traffic, but Atlas, embeddings, and Grafana traffic are variable |

Therefore, the realistic Azure-only estimate is:

- **Incremental cost with the existing ACR, PostgreSQL, Key Vault, monitoring workspace, and ACA environment already funded:** approximately **$65–$115/month** for low-to-moderate traffic, with **$200+** possible when the apps remain continuously active.
- **Attributing the full shared ACR and PostgreSQL resources to this service:** approximately **$100–$150/month** for low-to-moderate traffic, with **$240–$280/month** possible under sustained activity and higher Keycloak sizing.
- **Scale-to-zero experiment:** potentially much lower ACA compute, but not a reliable always-available service estimate.

MongoDB Atlas, Grafana Cloud, Voyage/API usage, taxes, support plans, and any NAT Gateway, private networking, Front Door, WAF, or APIM additions are excluded. Atlas tier selection is currently unspecified and could be the largest non-Azure variable. Prices and free-grant availability must be rechecked immediately before provisioning.

Pricing references: [Azure Container Apps pricing](https://azure.microsoft.com/en-us/pricing/details/container-apps/), [Azure PostgreSQL Flexible Server pricing](https://azure.microsoft.com/en-us/pricing/details/postgresql/flexible-server/), [Azure Monitor pricing](https://azure.microsoft.com/en-us/pricing/details/monitor/), and the [Azure Retail Prices API](https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview).

## 17. Historical VM parity fallback and lifecycle controls — 2026-08-31

The remainder of this document is retained for rollback planning and historical context. It is not part of the current Registry deployment and must not be combined with the Neo4j Bicep project or used to co-locate the Registry on the Neo4j VM.

For the first Azure canary, a single Linux VM is a viable alternative to the ACA baseline because it can run the existing `docker-compose.prebuilt.yml` with Compose networking and the local container topology intact. The recommended starting size is `Standard_B4as_v2` (4 vCPU, 16 GiB), subject to an application load test. This is a development/parity option, not a high-availability production design.

The VM deployment should support the following lifecycle controls:

- **Native portal control:** use the VM Overview `Stop` and `Start` actions. Confirm the resulting state is `Stopped (deallocated)`; `Stopped (allocated)` can continue to incur VM compute charges.
- **Nightly safety net:** configure the portal's VM auto-shutdown schedule so an unattended development VM is deallocated even when a manual stop is missed.
- **Dedicated one-click runbooks:** if a separate control is preferred, deploy an Azure Automation account with `Stop-RegistryVm` and `Start-RegistryVm` runbooks. The Automation account should use a system-assigned managed identity with a custom role scoped to this VM and limited to VM read, start, and deallocate actions. The runbooks must not require SSH credentials or application secrets and can be started manually from the Azure portal.

Stopping the VM only stops its compute host. MongoDB Atlas, Azure PostgreSQL, ACR, Key Vault, Grafana Cloud, and other external services continue independently and continue any applicable charges. Expose only the registry HTTPS ports through the VM network security group; keep database, OpenBao, Prometheus, Grafana, and administrative ports private or loopback-bound.

This option remains pending plan approval. No VM, Automation account, role assignment, or schedule has been created.

## 18. VM deployment resource inventory — 2026-08-31

The current resource group already contains `vnet-ai-access` in `westus3`, the ACR, Key Vault, PostgreSQL server, monitoring resources, and the existing shared data services. The VNet currently exposes `snet-tunnel` (`10.50.1.0/24`); the VM should use a separate dedicated subnet rather than reusing it without confirming its purpose. No VM, public IP, NSG, or Automation account was found in `rg-ai-access`.

### Required for a directly reachable VM

- One Linux VM using `Standard_B4as_v2`.
- One NIC and a private IP, created as part of the VM networking.
- A dedicated subnet in `vnet-ai-access`.
- A network security group allowing only the required HTTPS traffic and restricted administrative access.
- A static Standard public IP if the registry is directly internet-facing. A private-only VM would instead require a separate access or ingress service.
- One managed OS disk, created with the VM.
- A separate managed data disk is recommended for Docker volumes, logs, and Compose state if MongoDB CE and Keycloak PostgreSQL remain on the VM.
- A system-assigned VM identity with `AcrPull` on the existing ACR and read-only secret access on the existing Key Vault.

### Required only for custom portal runbooks

- One Azure Automation account.
- `Start-RegistryVm` and `Stop-RegistryVm` runbooks.
- A system-assigned Automation account identity.
- A custom role assignment scoped to this VM with only `Microsoft.Compute/virtualMachines/read`, `Microsoft.Compute/virtualMachines/start/action`, and `Microsoft.Compute/virtualMachines/deallocate/action`.

The native VM Overview `Start`/`Stop` actions and the VM auto-shutdown setting do not require the Automation account, runbooks, or a separate schedule resource. The custom runbooks are therefore optional convenience controls, not deployment prerequisites.

### Optional hardening and operations resources

- Recovery Services vault or managed-disk snapshots for backup and recovery.
- Azure Monitor Agent and a data collection rule if VM and Docker logs should be forwarded to the existing monitoring workspace.
- DNS records and a trusted certificate for a custom HTTPS hostname.
- Azure Bastion if SSH should not use a public IP. This adds cost and is not required for the initial development canary.
- Front Door, Application Gateway, WAF, NAT Gateway, or private endpoints only if later security, ingress, or egress requirements justify them.

The VM stop automation does not stop MongoDB Atlas, Azure PostgreSQL, ACR, Key Vault, Grafana Cloud, or other external services; those resources remain available and bill independently.

## 19. Existing VM reuse review - 2026-08-31

The subscription currently has two deallocated Linux VMs:

| VM | Resource group | Size | Private IP | Public IP | Current state |
|---|---|---|---|---|---|
| `vm-neo4j-neo4j` | `RG-NEO4J` | `Standard_D2s_v7` | `10.42.1.4` | Static Standard public IP attached | Deallocated |
| `lf-langfuse-produc-ch` | `RG-AI-LANGFUSE` | `Standard_D2s_v7` | `10.42.2.68` | None reported | Deallocated |

### Neo4j VM findings

- The VM uses `vnet-neo4j-neo4j` and subnet `neo4j` (`10.42.1.0/24`) in `RG-NEO4J`, rather than `vnet-ai-access`.
- Its subnet NSG currently allows SSH only from one `/32` operator address; it has no HTTP or HTTPS rule.
- It has a 32 GiB Standard SSD OS disk and a 64 GiB Standard SSD data disk. The data disk must not be reused or erased until the Neo4j data is backed up and the VM owner explicitly confirms retirement.
- It has a user-assigned identity with permissions for the Neo4j storage account and Neo4j Key Vault. That identity should not be reused for the registry; the registry should receive a separate system-assigned identity with only its ACR and deployment Key Vault permissions.
- An enabled VM auto-shutdown schedule already exists at `23:00` UTC with notifications disabled. It can be changed or retained after confirming the desired local time.

### Reuse decision

The Neo4j VM can technically host the Compose stack if Neo4j is retired, its data is preserved, the VM is resized to at least `Standard_B4as_v2`, and a fresh or deliberately reinitialized data disk is provided. Its existing static public IP, VNet, subnet, NSG, and auto-shutdown schedule could then be reused. This would avoid creating a second VM, NIC, public IP, VNet, and subnet.

Reuse is **not approved by inspection alone**. If Neo4j or Langfuse may be needed later, the safer choice is a new VM with separate networking and storage. A deallocated VM can still contain important disks, identities, DNS assumptions, and recovery material; deallocated does not mean disposable.

## 20. Neo4j and registry co-location decision - 2026-08-31

The selected development arrangement is to run Neo4j and the MCP Registry on the same VM, provided the existing Neo4j workload remains intact and both workloads are tested together. This is a valid cost-conscious development topology because it reuses the existing VM's networking, static public IP, and auto-shutdown schedule.

The expected Neo4j maximum is one user. This lowers expected concurrency, but Neo4j memory demand still depends on graph size, indexes, page cache, JVM heap, native memory, and transaction behavior. Explicit heap and page-cache limits should be set after running Neo4j's memory recommendation command on the retained dataset.

The current `Standard_D2s_v7` VM has 2 vCPU and 8 GiB. That may be sufficient only for a reduced registry deployment using external Atlas/PostgreSQL and without the bundled Prometheus/Grafana containers. For the full local-parity Compose profile, `Standard_B4as_v2` (4 vCPU, 16 GiB) remains the recommended minimum starting size; the registry's low memory usage does not remove Keycloak, database, monitoring, and Docker overhead. The actual allocation must be confirmed with a joint canary using host memory metrics, `docker stats`, and Neo4j workload measurements.

Co-location requirements:

- Keep Neo4j data and registry/Compose data in separate directories and preferably separate managed data disks. Do not erase or repurpose the existing 64 GiB Neo4j data disk.
- Expose only the registry HTTPS port publicly. Keep Neo4j Bolt/HTTP, databases, OpenBao, Prometheus, Grafana, and administrative ports private or restricted to the operator network.
- Treat VM stop, restart, resize, patching, and disk pressure as an outage event for both Neo4j and the registry. The existing auto-shutdown schedule currently deallocates the VM at `23:00` UTC, so it will stop both workloads.
- Do not reuse the Neo4j user-assigned identity for registry access. A separate registry identity is required, but identities attached to one VM are still a VM-level trust boundary rather than a strong per-container boundary; this arrangement is for development and is not equivalent to separate production hosts.
- Back up Neo4j and verify recovery before changing the VM size, disks, network rules, or Compose configuration.

This co-location decision supersedes the assumption that a new VM is automatically required, but it does not approve destructive changes to the Neo4j VM or its disks.

## 21. VM resize cost delta - 2026-08-31

The current Azure Retail Prices API rate for West US 3 Linux VMs is `$0.132/hour` for `Standard_D2s_v7` and `$0.150/hour` for `Standard_B4as_v2`. Using a 730-hour month:

| VM size | Capacity | Compute/month while running |
|---|---|---:|
| `Standard_D2s_v7` | 2 vCPU, 8 GiB | `$96.36` |
| `Standard_B4as_v2` | 4 vCPU, 16 GiB | `$109.50` |

The resize therefore adds approximately **`$0.018/hour` or `$13.14/month`**, a 13.6% compute increase for twice the vCPU and memory. This excludes disks, public IP, bandwidth, monitoring, taxes, and discounts. Existing disks and network resources do not change price solely because the VM size changes; a new data disk would be additional.

The VM is currently deallocated, so neither size incurs VM compute charges until it is running. Disks and networking can continue to incur charges while deallocated. `Standard_B4as_v2` is burstable; sustained CPU-heavy Neo4j activity should be measured because the B-series credit model can throttle the VM after credits are exhausted.

## 22. Sanity check and local validation gate - 2026-08-31

### Verdict

The plan is not too premature as a design exercise, but Azure mutation is premature. The next step should be a local combined canary using the exact prebuilt Compose profile plus the retained Neo4j workload. This is the lowest-risk way to replace assumptions about startup ordering, authentication, storage, HTTPS, and resource use with observations before resizing or repurposing an Azure VM.

The current VM-first direction is coherent when it is treated as the initial execution path. The earlier ACA sections are preserved as a deferred alternative. The static Azure readiness scan identified optional AWS integrations and deferred A2A startup issues; those are not a reason to rewrite the selected VM profile when the configured path remains Keycloak, MongoDB CE, Voyage/LiteLLM, and `EGRESS_AUTH_ENABLED=false`. They become migration blockers only if an AWS-backed provider, Bedrock model, DocumentDB IAM, Cognito, AgentCore federation, or standalone Strands/A2A runtime is enabled. The operator's successful manual testing means the basic application behavior is not the immediate uncertainty.

The `docker compose down` output confirms which local containers and the Compose network existed. It does not prove that the services were healthy, that Keycloak callbacks worked, that search indexes initialized, or that data survived a restart. Those behaviors must be tested explicitly.

### Local canary sequence

1. Make a private working copy of the local environment configuration. Do not copy the credential-like value currently present in `.env.default`; replace it with an unmistakable placeholder and revoke or rotate it if it is genuine. Keep all signing secrets strong, identical where the registry/auth contract requires it, and outside source control.
2. Recreate the selected profile with `STORAGE_BACKEND=mongodb-ce`, `AUTH_PROVIDER=keycloak`, `KEYCLOAK_ENABLED=true`, `EGRESS_AUTH_ENABLED=false`, and the product-telemetry opt-out. Keep the standalone A2A agents disabled for this canary. Record which values `build_and_run.sh --prebuilt` and `init-keycloak.sh` generate or change, including files under `.oauth-tokens`.
3. Start the exact prebuilt Compose profile and verify container health, startup ordering, registry `/health`, auth-server readiness, Keycloak readiness, MongoDB readiness, and the absence of restart loops. Capture `docker ps`, `docker stats --no-stream`, host memory, CPU, disk, and filesystem usage while the stack is idle and while representative registry activity is running.
4. The user has already manually exercised the real user path, including Keycloak login and logout, registry API authentication, registry and scope reads, virtual MCP creation and use, MCP gateway routing, and the built-in `airegistry-tools` surface. Preserve any available evidence and repeat only if the deployed configuration differs from the tested configuration.
5. The user has already manually verified the expected local behavior, including persistence-related flows, according to their report. The remaining persistence gate is to document the exact restart/stop-start evidence and separately verify Neo4j backup and recovery. Do not remove Neo4j data while testing.
6. Run Neo4j's `neo4j-admin server memory-recommendation` against the retained dataset and set explicit heap and page-cache limits based on the recommendation and the joint workload measurements. Neo4j documents OS memory, heap, native memory, transactions, page cache, indexes, and vector indexes as separate consumers.
7. Test the Azure-facing security posture locally before deployment: trusted hostname handling, HTTPS termination/certificate behavior, `MCP_HTTPS_REQUIRED=true`, `SESSION_COOKIE_SECURE=true`, restricted administrative ports, and a public-surface inventory. The eventual VM NSG should expose only the registry HTTPS port and tightly restrict SSH; Neo4j Bolt/HTTP, databases, OpenBao, Prometheus, Grafana, and Keycloak administration must remain private or operator-restricted.

### Local canary exit criteria

The user-reported manual functional validation is accepted as the current baseline for the selected local configuration. The VM path is ready for an Azure change request only after the combined host has measured memory and disk headroom under representative use, Neo4j has a tested backup and recovery path, the exact persistence evidence is recorded, and the HTTPS/public-port design is explicit. These are acceptance criteria for this deployment, not claims about Azure product limits.

### Azure change gate after the canary

1. Confirm Neo4j ownership and complete a verified backup/restore before changing the existing VM size, disks, subnet, NSG, identity, or auto-shutdown schedule.
2. Keep Neo4j data and Compose data on separate storage paths; do not reuse or erase the existing 64 GiB Neo4j data disk. Add a separate data disk if the local MongoDB CE and Keycloak PostgreSQL containers remain on the VM.
3. Prefer the existing VM only if the canary supports co-location. Resize from `Standard_D2s_v7` to `Standard_B4as_v2` only after the backup and measurement gate; the latter is a 4-vCPU/16-GiB burstable size, and its CPU-credit behavior must be monitored for sustained workloads.
4. Use a separate registry managed identity rather than the existing Neo4j identity. Decide whether the VM pulls public prebuilt images directly or mirrors verified immutable images to ACR; do not deploy mutable `latest` references without an explicit exception.
5. Confirm the existing `23:00` UTC auto-shutdown schedule before reusing it. Azure documents that auto-shutdown time is UTC by default, and only the `Deallocated` state stops VM compute billing; disks and networking can continue to incur charges.

### Evidence for this decision

- Local profile and startup behavior: `.env.default`, `docker-compose.prebuilt.yml`, `build_and_run.sh`, `keycloak/setup/init-keycloak.sh`, `registry/main.py`, and `registry/repositories/documentdb/*`; functional behavior is additionally operator-confirmed as of 2026-08-31.
- AWS-path scope: `pyproject.toml`, `auth_server/server.py`, `registry/utils/mongodb_connection.py`, `registry/utils/cognito_manager.py`, `registry/services/federation/agentcore_client.py`, `cli/package.json`, and `agents/a2a/pyproject.toml`.
- VM size and CPU-credit behavior: [Basv2 size series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/basv2-series).
- Auto-shutdown behavior and UTC default: [Auto-shutdown a VM](https://learn.microsoft.com/en-us/azure/virtual-machines/auto-shutdown-vm).
- Deallocated-state billing: [States and billing status](https://learn.microsoft.com/en-us/azure/virtual-machines/states-billing).
- Neo4j memory consumers and recommendation command: [Neo4j memory configuration](https://neo4j.com/docs/operations-manual/current/performance/memory-configuration/).

## 23. Neo4j deployment-project integration finding - 2026-08-31

The supplied `/home/rpl/Projects/NLAI/azd-neo4j` project does contain `azure.yaml`, but it does not contain a Neo4j Docker Compose file. It is an Azure Developer CLI project whose `azure.yaml` points to Bicep under `infra/`; the Bicep creates a resource group, VNet, subnet, NSG, public IP, managed identity, Key Vault, backup storage, VM, disks, and an optional auto-shutdown schedule. Running it unchanged would describe a new Neo4j deployment, not add Neo4j to the existing MCP Registry VM.

The authoritative Neo4j guest configuration is Ansible plus a systemd service. The service runs a pinned Neo4j image under rootless Podman as the `neo4j` user, binds ports 7474 and 7687 to VM loopback, and mounts `/var/lib/neo4j/{data,logs,import,backups,plugins}`. This is a strong source for the Neo4j image, memory defaults, plugin mounts, port policy, and storage boundaries, but it is not a Compose service that can be copied verbatim.

The safest experiment is therefore two-stage:

1. For local testing, derive a disposable Neo4j Compose overlay from the pinned image, environment settings, loopback-only port policy, memory limits, and separate named volumes. Run it alongside the already-tested registry Compose profile without touching the Azure VM or the existing Neo4j data disk.
2. For Azure reuse, preserve the existing systemd/Podman Neo4j service and extend the `azd-neo4j` Ansible/Bicep deployment boundary with the registry runtime. Do not start a second Neo4j container against `/var/lib/neo4j` and do not run the current `azure.yaml` unchanged when the goal is to reuse an existing VM.

The registry repository supports a Podman Compose variant, but `build_and_run.sh --podman` still performs an unconditional `docker compose version` check later in the script (`build_and_run.sh:229-234`). Before using that script on the Neo4j host, either correct that runtime-specific check or use an explicitly reviewed Podman invocation. This is a directly observed integration issue, not a reason to install Docker or modify the Azure VM yet.

Evidence: `/home/rpl/Projects/NLAI/azd-neo4j/azure.yaml`, `infra/main.bicep`, `infra/modules/neo4j-vm.bicep`, `ansible/templates/neo4j.service.j2`, `ansible/templates/neo4j.env.j2`, `README.md`, and this repository's `docker-compose.podman.yml` and `build_and_run.sh`.

## 24. WSL memory constraint and Neo4j integration decision - 2026-08-31

The registry repository has no Neo4j client, connection setting, driver, or endpoint. Neo4j is therefore an adjacent workload, not a current runtime dependency of the MCP Registry. Adding Neo4j to the local Compose profile would consume memory without exercising an integration that the registry currently performs.

The local combined canary is revised because the WSL host is not expected to have enough memory for Neo4j plus the full registry profile. The recommended development topology is:

- Run the already-tested MCP Registry Compose profile in WSL.
- Keep Neo4j on the existing Azure VM under its current rootless Podman/systemd service and retain its loopback-only ports and dedicated data disk.
- When a local Neo4j client or future MCP server needs the database, use an SSH tunnel to a non-conflicting local port, for example `ssh -N -T -o ExitOnForwardFailure=yes -L 17687:127.0.0.1:7687 <operator>@<neo4j-public-ip>`, and connect that client to `bolt://127.0.0.1:17687`. Do not expose Bolt or Browser ports publicly.
- If a containerized client later needs Neo4j, give that client an explicit host-gateway/tunnel or private-IP route and verify the resulting firewall boundary; do not assume that `127.0.0.1` inside a container reaches the VM's Neo4j loopback listener.

For the eventual Azure co-location deployment, keep Neo4j and the registry as independent services on the same VM rather than putting Neo4j into the registry Compose project. Neo4j should remain managed by its existing `neo4j.service` and `neo4j` account. The registry should use a separate account, environment directory, storage path or data disk, managed identity, and systemd unit. Only the registry HTTPS listener should be public. This preserves independent restarts and prevents an experiment from mounting or modifying `/var/lib/neo4j`.

### Why the Neo4j Ansible playbook exists

`azure.yaml` selects Bicep for Azure resource provisioning; Bicep creates the VM, disks, network, identity, Key Vault, backup storage, and auto-shutdown schedule but does not provide a repeatable guest-OS configuration lifecycle. The VM's `customData` is intentionally only a transport wrapper: it installs `ansible-core`, writes the checked-in playbook and templates, and invokes Ansible locally with `ansible_connection=local`.

The playbook supplies the safe, repeatable host convergence that a one-shot container command would not provide. It installs rootless-Podman prerequisites, creates the dedicated account, identifies and validates exactly the intended data-disk LUN, refuses ambiguous or unsafe filesystem states, persists the mount by UUID, repairs rootless user-namespace ownership, retrieves the initial password through managed identity and Key Vault, renders the environment and systemd unit, verifies pinned plugins, preserves the prior service state, and gates completion on authenticated Neo4j health checks. It is not required for the registry to run in Compose; it is the configuration and recovery mechanism for the Neo4j VM.

This supersedes the local disposable-overlay recommendation in section 23. The overlay remains a possible isolated test artifact, but it is not required and should not be attempted on a memory-constrained WSL host.

## 25. Why the Neo4j playbook is larger than a Compose file - 2026-08-31

The comparison is valid, but it compares different responsibilities. A small Compose file can start a disposable Neo4j container; it cannot safely perform all of the host and data lifecycle work required by the Azure VM deployment.

| Responsibility | Simple Compose | Existing Neo4j playbook |
|---|---|---|
| Start the container | Yes | Yes, through systemd and rootless Podman |
| Persist data | Bind or named volume | Validates the exact Azure LUN, rejects unsafe filesystem states, mounts by UUID, and verifies the mount before writing |
| Protect retained data | Operator-dependent | Never formats an already-mounted disk and preserves the existing service/data boundary |
| Secrets | Environment or an external secret mechanism must be added | Retrieves the initial password through managed identity and Key Vault, writes it atomically, and suppresses secret output |
| Reproducibility | Depends on host preparation | Installs required packages, dedicated user, rootless user-namespace ownership, lingering, and systemd configuration |
| Supply-chain controls | Must be added separately | Pins the image and verifies plugin checksums before installation |
| Recovery and operations | Must be added separately | Installs backup and password-rotation helpers and gates completion on authenticated health checks |

For a disposable development database, the playbook is more than necessary. For the existing Azure VM, the disk, secret, plugin, least-privilege, and recovery safeguards are the reason it is intentionally more complex. The practical middle ground is to keep this playbook responsible only for Neo4j and deploy the Registry separately with its own systemd-managed Compose/Podman unit; do not replace the Neo4j playbook with a Compose file unless the data disk and secret/recovery controls are deliberately redesigned.

## 26. Estimated integration effort - 2026-08-31

There are two different meanings of "integrate the project with Neo4j":

1. **Co-locate the existing Registry deployment with the existing Neo4j service.** This is a deployment integration, not an application rewrite. A realistic estimate is approximately **1-3 engineering days plus Azure validation**, assuming the existing VM, Neo4j data, and local Registry configuration remain unchanged.
2. **Make the Registry application itself use Neo4j.** The current repository has no Neo4j driver, connection setting, repository, or endpoint. That is a new product/data-model feature, not a deployment task. A basic implementation would likely require **1-2 weeks** after the graph use cases, ownership of MongoDB versus Neo4j data, schema, authentication, and consistency requirements are defined; production hardening could take longer.

The recommended deployment work is:

- Add a separate `mcp_registry` Ansible role or playbook path; keep the existing Neo4j tasks and data-disk safeguards unchanged.
- Install the selected container runtime and run the Registry as a separate project under a dedicated account, storage path, environment file, and systemd unit.
- Prefer the repository's rootless Podman-compatible Compose path to match the Neo4j host. If Docker Engine/Compose is required, install and manage it explicitly through Ansible and validate coexistence with the existing rootless Podman service; this introduces a second runtime and a rootful daemon.
- Supply Registry secrets through Key Vault or another protected mechanism, deploy immutable image references, configure HTTPS, and expose only the Registry edge and restricted SSH.
- Add a deployment smoke test, rollback procedure, and resource measurements. If no component actually calls Neo4j, no Neo4j network change is needed.

The main uncertainty is not the number of YAML files; it is whether a Registry or MCP component must make live Bolt queries. If so, the network route, credentials, driver configuration, graph schema, and integration tests must be designed separately. If not, the two systems can remain independent services that merely share the VM.
