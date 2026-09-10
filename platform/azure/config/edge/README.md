# Azure edge runtime

The edge VM runs Apache APISIX and a remotely managed Cloudflare Tunnel connector. The connector joins the existing tunnel `mcp-gateway-registry-edge`; it does not create or modify Cloudflare account resources.

APISIX connects to the private etcd endpoint with client mTLS and exposes its data listener on `10.60.1.4:9080`. Its Admin API is bound to the VM loopback address only. The cloudflared container reads its tunnel run token from `/etc/platform/secrets/cloudflare-tunnel-token` using `--token-file`, so the token is not placed in a process argument or source-controlled file.

Before enabling `platform-edge.service`, create `/etc/platform/config/edge-origin.env` from the example with the private Registry and Keycloak origin addresses, schemes, ports, and public host headers. The bootstrap renderer validates these values, creates both APISIX routes, and writes the protected Compose environment from the Key Vault-synchronized APISIX Admin API key. VM origins use HTTP on port 8080 because TLS terminates at APISIX; the ACA rollback origins use HTTPS on port 443.

The Cloudflare API token is an operator credential for account management and is not required on the edge VM. The existing tunnel token must be seeded separately into the platform Key Vault under `cloudflare-tunnel-token`.

All externally initiated application traffic must traverse the Cloudflare
Tunnel and APISIX chain. Application and platform workloads must not expose
alternate public ingress paths or bypass APISIX; workload-to-workload private
traffic is separate from external ingress and remains governed by the platform
network and service contracts.
