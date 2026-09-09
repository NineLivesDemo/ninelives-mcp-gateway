# Platform secret seeding

Secret values are operator-managed and must not be committed to this repository. Seed the platform Key Vault before enabling `deployRuntimeAccess` or `deployApps`.

The operator performing seeding also needs a Key Vault data-plane role on the
target vault, such as a deliberately time-limited `Key Vault Secrets Officer`
assignment. Azure subscription `Owner` or `Contributor` management access does
not automatically grant permission to list or write secret metadata and
values.

Use files or stdin rather than `--value` so secret material is not placed in shell history or process arguments:

```bash
az keyvault secret set \
  --vault-name "$PLATFORM_KEY_VAULT_NAME" \
  --name "platform-ca-cert" \
  --file "$SECRET_DIR/platform-ca.crt"
```

The platform seeding helper validates the complete runtime mapping and supports
a dry run:

```bash
platform/azure/scripts/secrets/seed-platform-secrets.sh \
  "$PLATFORM_KEY_VAULT_NAME" \
  "$HOME/platform-secrets" \
  --dry-run
```

After review, run it without `--dry-run`. It reads each value with
`az keyvault secret set --file`, so secret material is not placed on process
arguments. The helper requires a Key Vault data-plane role and intentionally
does not seed application secrets, including the deferred MongoDB URL.

## Runtime secrets

The VM modules expect these platform secrets:

| Secret | Consumer |
| --- | --- |
| `cloudflare-tunnel-token` | Edge cloudflared |
| `apisix-admin-key` | Edge APISIX route bootstrap |
| `grafana-otlp-edge` | Edge Alloy |
| `grafana-otlp-etcd` | etcd Alloy |
| `grafana-otlp-openbao` | OpenBao Alloy |
| `platform-ca-cert` | All platform services |
| `etcd-server-cert` / `etcd-server-key` | etcd listener |
| `etcd-edge-client-cert` / `etcd-edge-client-key` | Edge APISIX client |
| `etcd-health-client-cert` / `etcd-health-client-key` | etcd health check |
| `openbao-tls-cert` / `openbao-tls-key` | OpenBao listener |

The etcd client pairs are intentionally separate identities. Use distinct certificates even though both connect to the same private etcd listener.

The TLS generator uses file extensions, while the seeding helper expects the
secret name as the file name. Copy or rename only these files into the seed
directory:

| Generated file | Seed file |
| --- | --- |
| `platform-ca.crt` | `platform-ca-cert` |
| `etcd-server.crt` | `etcd-server-cert` |
| `etcd-server.key` | `etcd-server-key` |
| `etcd-edge-client.crt` | `etcd-edge-client-cert` |
| `etcd-edge-client.key` | `etcd-edge-client-key` |
| `etcd-health-client.crt` | `etcd-health-client-cert` |
| `etcd-health-client.key` | `etcd-health-client-key` |
| `openbao-tls.crt` | `openbao-tls-cert` |
| `openbao-tls.key` | `openbao-tls-key` |

Never copy `platform-ca.key`; it must remain offline.

## Application secrets

When `deployApps=true`, the ACA module expects these Key Vault secret names by default:

| Secret | Consumer |
| --- | --- |
| `registry-secret-key` | Registry and auth-server |
| `auth-server-nginx-marker-secret` | Registry and auth-server |
| `mongodb-connection-string` | Registry; seed or replace this only when the final MongoDB URL is available and approved |
| `embeddings-api-key` | Registry |
| `keycloak-admin-password` | Keycloak |
| `keycloak-client-secret` | Registry and auth-server |
| `keycloak-m2m-client-secret` | Registry |
| `keycloak-db-password` | Keycloak |
| `openbao-registry-token` | Registry OpenBao egress credential store |

Application secret names are parameters and may be changed in the deployment-specific parameter file. The corresponding secrets must exist before the application tier is enabled. `openbao-registry-token` must be a restricted token with access only to the Registry egress KV prefix; never use an OpenBao root or recovery token.

### Temporary database endpoint

The existing demo MongoDB URI can be used temporarily by writing it to the
`mongodb-connection-string` secret. The application already gives this full URI
precedence over the discrete `DOCUMENTDB_*` settings, so changing the endpoint
does not require a code or image change. Use file input and never place the URI
in a parameter file, shell command argument, log, or committed environment file:

```bash
az keyvault secret set \
  --vault-name "$APPLICATION_KEY_VAULT_NAME" \
  --name mongodb-connection-string \
  --file "$MONGODB_URI_FILE"
```

After changing the value, restart or roll the application revision so the
process receives the new secret. Run the MongoDB initialization and index checks
against the selected database. Replacing the demo URI later is the same
operation; a data migration is only required if data must be retained across
the two deployments.

The existing local trial database can remain in use during platform
preparation. Do not copy its URI into the platform Key Vault when the intent is
to migrate to another database; replace `mongodb-connection-string` only after
the new endpoint and credentials are available.

## Seeding order

1. Create the platform Key Vault and confirm the intended secret names.
2. Seed the CA certificate, role-specific certificates, endpoint credentials, and tunnel/API keys.
3. Run a runtime-only `what-if` with `deployRuntimeAccess=true`.
4. Apply the runtime access deployment and verify the VM identities receive only their declared secret-scope assignments.
5. Seed finalized application secrets and publish immutable application images to the selected ACR; the MongoDB connection string may remain deferred.
6. Before enabling `deployApps=true`, update `mongodb-connection-string` with the final MongoDB URL, verify network access and credentials, and run the application `what-if`.

Do not seed OpenBao recovery keys or root tokens in Azure Key Vault. Keep them offline under the operator-controlled recovery procedure.
