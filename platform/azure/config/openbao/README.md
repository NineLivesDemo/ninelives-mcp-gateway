# OpenBao runtime configuration

This is the single-node Azure pilot configuration for OpenBao. It uses integrated Raft storage on `/var/lib/platform/data/openbao`, serves private TLS on `10.60.3.4:8200`, and does not publish the Raft cluster port `8201`.

The `azurekeyvault` seal uses the OpenBao VM system-assigned managed identity. No Azure client secret is required. The identity receives only the cryptographic permission for the `openbao-unseal` Key Vault key.

Before enabling the Compose service, render `openbao.hcl` with the Azure tenant ID and platform Key Vault name, install it under `/opt/platform/config/openbao/openbao.hcl`, and provide the non-secret environment file under `/etc/platform/config/openbao.env`. The systemd unit requires the protected secret-sync service and fails closed if TLS synchronization fails:

```text
/etc/platform/tls/platform-ca.crt
/etc/platform/tls/openbao.crt
/etc/platform/tls/openbao.key
```

OpenBao initialization, policies, AppRole setup, Doppler synchronization, and recovery-key handling remain operator-controlled post-provisioning steps.
