# Platform TLS material

The platform CA remains offline. Only the CA certificate and role-specific leaf material are synchronized to VMs through Azure Key Vault.

| Key Vault secret | Consumer | Required identity/SAN |
| --- | --- | --- |
| `platform-ca-cert` | All platform services | CA certificate only |
| `etcd-server-cert` / `etcd-server-key` | etcd | `etcd.platform.internal`, `10.60.2.4` |
| `etcd-edge-client-cert` / `etcd-edge-client-key` | APISIX on edge | etcd client identity |
| `etcd-health-client-cert` / `etcd-health-client-key` | etcd health check | separate etcd client identity |
| `openbao-tls-cert` / `openbao-tls-key` | OpenBao | `openbao.platform.internal`, `10.60.3.4` |

Client certificates are intentionally separate even when they reach the same etcd listener. This permits independent rotation and revocation. Certificate values are not stored in this repository.

## Generate the initial set

Run the generator on an operator-controlled host with a new, empty output
directory:

```bash
mkdir -m 700 "$HOME/platform-tls-$(date +%Y%m%d)"
platform/azure/scripts/tls/generate-platform-certificates.sh \
  "$HOME/platform-tls-$(date +%Y%m%d)"
```

The generator creates a ten-year offline CA and 825-day leaf certificates
with the SANs and identities listed above. It refuses to overwrite a
non-empty directory. Keep `platform-ca.key` offline and never upload it to
Key Vault or a VM. Seed only the certificate/key pairs and CA certificate
under the exact Key Vault secret names in the table.

The generated private keys are unencrypted files protected by filesystem mode
`0600` because the runtime services must read their leaf keys. Protect the
operator output directory and transfer the mapped values to Key Vault through
the approved secret-seeding process.
