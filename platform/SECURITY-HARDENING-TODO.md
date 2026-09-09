# Platform production hardening TODO

This checklist captures the remaining work before exposing the company web application more broadly. It is intentionally practical for a small deployment; a formal enterprise threat-modeling exercise is not required.

## Current baseline

- [x] Keep application origins private inside the internal Azure Container Apps environment.
- [x] Route external traffic through Cloudflare Tunnel and the APISIX edge.
- [x] Protect the APISIX Dashboard with Cloudflare Access, Keycloak, and the approved operator IP.
- [x] Restrict the APISIX Admin API to the edge host and trusted Docker network.
- [x] Use strict mTLS for APISIX-to-etcd communication.
- [x] Store runtime secrets in Key Vault with per-service access.
- [x] Establish private PostgreSQL connectivity with a private endpoint.

## Before broader release

- [ ] Enable and verify certificate validation, CA trust, and SNI for APISIX HTTPS upstreams, especially Keycloak.
- [x] Remove query strings from APISIX access logs so OIDC state, codes, and other parameters are not retained.
- [ ] Enable MFA for the Keycloak administrator.
- [ ] Review and shorten the Cloudflare Access session duration where appropriate.
- [ ] Add login rate limiting and alerting for the Keycloak public OIDC surface.
- [ ] Confirm that only intended hostnames are configured in the Cloudflare Tunnel and that ACA origins are not publicly reachable.
- [ ] Disable PostgreSQL public network access after all remaining clients are confirmed to use the private path.
- [ ] Remove unused applications, DNS records, tunnel routes, identities, role assignments, secrets, and supporting Azure resources.
- [ ] Rotate credentials and tunnel/API tokens after cleanup and verify their Key Vault permissions.
- [ ] Scan pinned images and dependencies for vulnerabilities and establish a patching cadence.
- [ ] Add monitoring and alerts for authentication failures, edge 4xx/5xx responses, container restarts, and certificate expiry.
- [ ] Document backup and restore procedures for PostgreSQL, Keycloak, and platform configuration; perform a restore test.
- [ ] Decide whether the single edge VM and single Keycloak replica meet the application's availability target.
- [ ] Maintain concise operational runbooks for deployment, credential rotation, incident response, and recovery.

## Lightweight security review

- [ ] List the application's sensitive assets and privileged accounts.
- [ ] Document the trust boundaries: Internet, Cloudflare, edge VM, VNet, ACA, database, and Key Vault.
- [ ] Review the five most plausible abuse cases and confirm a preventive or detective control for each.
