# Azure edge deployment handoff

> Historical legacy deployment handoff from 2026-09-08. Its `RG-EDGE`,
> `RG-ETCD`, `vm-platform-*`, and `10.60.*.4` values do not describe the
> current Terraform deployment. Use `platform-dev-handoff-2026-09-10.md` and
> current Terraform outputs for the replacement environment.

## Outcome

The ACA application tier is deployed and healthy. The Cloudflare/APISIX edge is not complete. Docker Engine and Docker Compose are in use; Podman is not involved.

## Azure resources

- Subscription: `f1129652-3166-4f34-8d4c-5cf35bffbcdc`
- Region: `westus3`
- Edge VM: `RG-EDGE/vm-platform-edge`, private IP `10.60.1.4`
- etcd VM: `RG-ETCD/vm-platform-etcd`, private IP `10.60.2.4`
- Platform Key Vault: `kvplatformrtsxkr2fmvx42`
- ACA Registry origin: `mcp-registry.internal.calmpond-768ed6e9.westus3.azurecontainerapps.io`
- Intended public hosts:
  - `registry-github.adriangarciacruz.com`
  - `keycloak.adriangarciacruz.com`

## Current runtime state

- ACA Registry, auth-server, MCP gateway, and Keycloak are healthy.
- etcd is running and its Docker healthcheck is healthy.
- Host-side mTLS from the edge VM to `https://etcd.platform.internal:2379/version` succeeds.
- `platform-edge.service` is still failed.
- `platform-apisix` remains in a restart loop.
- `platform-apisix-bootstrap` exits because APISIX never becomes ready.
- cloudflared has not been verified as connected.
- Public DNS, tunnel ingress, public HTTPS health, and login flows are unverified.

## Work completed in this turn

Remote changes:

- Bootstrapped the previously uninitialized etcd VM.
- Added the etcd VM managed identity's `Key Vault Secrets User` role on the platform Key Vault.
- Corrected the etcd secret-sync vault URI to the platform vault.
- Corrected remote directory/file permissions for edge mounts.
- Converted the `etcd-edge-client-key` Key Vault secret to traditional RSA PEM (`BEGIN RSA PRIVATE KEY`).

Repository changes:

- `platform/azure/scripts/bootstrap/host-bootstrap.sh`: container-readable `/opt/platform` and TLS directory permissions.
- `platform/azure/scripts/bootstrap/platform-edge-files.sh`: readable edge directories and executable bootstrap script.
- `platform/azure/scripts/bootstrap/platform-edge-render.py`: route output mode changed to `0644`.
- `platform/azure/scripts/bootstrap/platform-etcd-files.sh`: etcd compose directory mode changed to `0755`.
- `platform/azure/scripts/secret-sync/platform-secret-sync.py`: TLS certificates are `0644`; TLS keys are `0640` and group-owned by APISIX UID/GID `636`; ordinary secrets remain `0600`.
- `platform/azure/config/etcd/compose.yaml`: healthcheck changed from unavailable `CMD-SHELL` to exec-form `etcdctl`, with `ETCDCTL_API=3`.
- `platform/azure/scripts/tls/generate-platform-certificates.sh`: generated RSA leaf keys are converted to traditional RSA PEM for APISIX/OpenResty compatibility.

The changed Python and shell files compile/syntax-check successfully, Compose configuration validates, and `git diff --check` passes.

## Immediate blocker

The original APISIX key and CA problems were isolated and fixed:

- The APISIX image runs as `uid=636(apisix)`, so TLS directory traversal and key group permissions were corrected.
- The client key was converted from PKCS#8 (`BEGIN PRIVATE KEY`) to traditional RSA PEM (`BEGIN RSA PRIVATE KEY`).
- APISIX now loads the key and reaches the etcd endpoint.
- The APISIX image's OpenSSL client and host-side `curl` both complete mTLS successfully.

APISIX's Lua etcd client still fails during its gRPC request:

```text
got malformed key-put message:
{"error":"connection error: desc = \"error reading server preface: remote error: tls: bad certificate\""}
```

The etcd-side log reports `tls: bad record MAC` for APISIX connections. The APISIX Lua client uses `lua-resty-etcd`/gRPC and passes client certificate paths, while direct OpenSSL and curl succeed. The likely remaining issue is APISIX's Lua/gRPC TLS implementation or its interaction with this etcd listener, not Azure networking, DNS, file permissions, or the certificate/key pair.

Strict verification was restored on the remote APISIX configuration before stopping. Do not leave `verify: false` enabled.

The APISIX configuration now includes:

```yaml
apisix:
  ssl:
    ssl_trusted_certificate: /etc/apisix/tls/platform-ca.crt
```

This fixed CA loading but did not fix the subsequent gRPC `bad certificate` failure.

Useful checks:

```bash
az vm run-command invoke \
  --resource-group RG-EDGE \
  --name vm-platform-edge \
  --subscription f1129652-3166-4f34-8d4c-5cf35bffbcdc \
  --command-id RunShellScript \
  --scripts 'docker logs --tail 100 platform-apisix 2>&1' \
           'stat -c "%A %a %U:%G %n" /etc/platform/tls/*' \
  --query "value[].message" -o tsv
```

Suggested next investigation:

1. Reproduce the APISIX `lua-resty-etcd` gRPC connection with a minimal APISIX/Lua test using the same mounted cert, key, SNI, and CA.
2. Inspect the bundled gRPC client options and TLS version behavior; direct `openssl s_client` from the APISIX image succeeds with TLS 1.3.
3. Compare APISIX's gRPC request with `etcdctl`/curl, and test a compatible pinned APISIX image or etcd client configuration without weakening TLS verification.

After APISIX stays running:

1. Restart or start `platform-edge.service` and confirm `platform-apisix-bootstrap` returns success.
2. Query the loopback Admin API on `127.0.0.1:9180` and confirm the Registry route exists.
3. Verify `platform-cloudflared` is connected and that tunnel ingress maps both public hostnames to APISIX `http://10.60.1.4:9080`.
4. Test public Registry health and Keycloak HTTPS/login flows.
5. Rotate the Cloudflare API token that was previously exposed during the session.
6. Reapply/rebootstrap from repository sources so remote repairs are not lost. Run the required `azure-validate` workflow before any Azure deployment and do not manually set the deployment-plan status.

## Caution

Do not print, paste, or repeat any secret, token, private key, MongoDB URI, or credential value. The Cloudflare API token exposure was acknowledged by the user, but rotation remains required.
