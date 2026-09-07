# Azure Container Apps Prerequisite Readiness

Session: `5bd87998-fca1-4b76-a51f-e09a24005152`

Scan commit: `82f8c4b1b0f2953332e3fd99869ac4ecdb4a0199`

Evaluation mode: static repository analysis only. No application source was modified.

## Result

Overall status: **BLOCKED pending remediation and cloud-SDK migration decisions**.

Azure Container Apps is a viable hosting target for the containerized web/API and optional worker surfaces. The repository is not ready for Azure architecture or infrastructure generation yet because it still contains functional AWS integrations and both A2A images use a runtime `uv run` command that the prerequisite policy treats as a startup blocker.

## Component verdicts

| Component | Build | Completeness | Deployability |
|---|---:|---:|---:|
| registry-api | WARN | PASS | WARN |
| auth-server | WARN | PASS | WARN |
| metrics-service | WARN | PASS | WARN |
| frontend | PASS | WARN | WARN |
| cli | PASS | PASS | WARN |
| mcp-currenttime | WARN | PASS | WARN |
| mcp-fake-tools | WARN | PASS | WARN |
| mcp-gateway | WARN | PASS | WARN |
| a2a-agents | WARN | PASS | FAIL |

The primary registry health endpoint is `/health` through the nginx edge, with uvicorn listening internally on port `7860` and nginx serving the external HTTP surface on port `8080`.

## Major migration blockers

| ID | Component | Dependency | Azure replacement |
|---|---|---|---|
| CLOUD-SDK-REGISTRY-AWS | registry-api | boto3 / botocore | MongoDB Atlas or Cosmos DB for MongoDB, Entra ID, Key Vault, and managed identity |
| CLOUD-SDK-REGISTRY-BEDROCK | registry-api | langchain-aws and Bedrock model paths | Azure OpenAI or another OpenAI-compatible embedding endpoint |
| CLOUD-SDK-AUTH-COGNITO | auth-server | boto3 Cognito integration | Microsoft Entra ID or Entra External ID |
| CLOUD-SDK-CLI-BEDROCK | cli | @aws-sdk/client-bedrock-runtime | Azure OpenAI or another supported model API |
| CLOUD-SDK-A2A-STRANDS | a2a-agents | strands-agents and AgentCore toolkit | Azure OpenAI-compatible agent implementation or disable A2A images |

These integrations are optional in parts of the repository, but any enabled path must be swapped or explicitly disabled before an Azure deployment can be planned.

## Critical deployment fix

`W-UV-RUN` affects both `agents/a2a/src/travel-assistant-agent/Dockerfile` and `agents/a2a/src/flight-booking-agent/Dockerfile`. Replace the runtime `uv run --no-sync` commands with direct `/app/.venv/bin/python` commands and re-evaluate the A2A component.

## Warnings

| ID | Component | Area | Action |
|---|---|---|---|
| W-NATIVE-REGISTRY | registry-api | Build | Build the native/scientific dependency tree in ACR and use a paid Container Apps profile. |
| W-MULTIPROCESS-REGISTRY | registry-api | Runtime | Keep nginx and uvicorn together only with explicit supervision and probes, or split them. |
| W-REGISTRY-PORTS | registry-api | Networking | Use 8080 as the sole ingress target; keep 7860 internal. |
| W-REGISTRY-LOCAL-STATE | registry-api | Storage | Move logs, scans, mappings, certificates, and models to durable services. |
| W-COMPOSE-HOSTNAMES-REGISTRY | registry-api | Configuration | Replace Compose DNS names with managed endpoints or internal Container Apps DNS. |
| W-LOCALHOST-URL-REGISTRY | registry-api | Configuration | Set production HTTPS URLs and trusted hosts. |
| W-NATIVE-AUTH | auth-server | Build | Build the native dependency tree in ACR. |
| W-AUTH-BIND | auth-server | Networking | Keep the auth service private and do not expose its raw port. |
| W-IDP-PROVIDER-DEFAULT | auth-server | Identity | Choose Entra ID or separately hosted production Keycloak instead of the Cognito default. |
| W-COMPOSE-HOSTNAMES-AUTH | auth-server | Configuration | Replace Compose-only database, registry, metrics, and IdP hostnames. |
| W-NATIVE-METRICS | metrics-service | Build | Build the native dependency tree in ACR. |
| W-SQLITE-METRICS | metrics-service | Storage | Use Azure Files for one replica or migrate to a managed database. |
| W-FAVICON | frontend | Assets | Add `frontend/public/favicon.ico` or remove the reference. |
| W-LOCALHOST-URL-FRONTEND | frontend | Configuration | Supply production frontend auth and API URLs. |
| W-CLI-NONDEPLOYABLE | cli | Mapping | Treat the CLI as a separately published client artifact. |
| W-NATIVE-MCP-CURRENTTIME | mcp-currenttime | Build | Build the native dependency tree in ACR. |
| W-TCP-PROBE-CURRENTTIME | mcp-currenttime | Probes | Use a TCP probe or add an HTTP health route. |
| W-NATIVE-MCP-FAKE | mcp-fake-tools | Build | Build the native dependency tree in ACR. |
| W-TCP-PROBE-FAKE | mcp-fake-tools | Probes | Keep the sample internal and use a TCP probe if deployed. |
| W-NATIVE-MCPGW | mcp-gateway | Build | Build the native dependency tree in ACR. |
| W-MCPGW-REGISTRY-URL | mcp-gateway | Configuration | Set `REGISTRY_BASE_URL` to the deployed registry endpoint. |
| W-COMPOSE-HOSTNAMES-MCPGW | mcp-gateway | Configuration | Replace Compose service discovery with Container Apps internal DNS. |
| W-NATIVE-A2A | a2a-agents | Build | Build in ACR and replace or disable AWS-oriented model integration. |
| W-SQLITE-A2A | a2a-agents | Storage | Move agent state to a managed datastore or constrain to one durable replica. |

## Detected deployment inventory

The repository contains Dockerfiles, Docker Compose, Helm charts, and GitHub Actions. No Azure-specific `azure.yaml`, Bicep, or Terraform configuration was detected.

Compose-managed dependencies include MongoDB 8.2, PostgreSQL 16 for Keycloak, OpenBao 2.5.5, Keycloak 25.0, Prometheus v3.11.3, Grafana 12.3.1, and optional PingFederate 13.0.2. MongoDB is also used by the application code as the primary registry and auth persistence layer.

Metrics and both A2A agents use SQLite/local filesystem state. The registry also writes generated configuration, security scans, certificates, logs, and optional local embedding models to the container filesystem.

## Routing boundary

The prerequisite artifacts are complete at `context.json` and `prereq-output.json`. Azure architecture planning and IaC generation must wait until the A2A startup fix is addressed or accepted as a risk and the required AWS-to-Azure migration decision is made.
