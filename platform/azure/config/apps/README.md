# Registry application VM

The application VM runs the Registry, auth-server, and MCP gateway as three
immutable ACR images in Docker Compose. Keycloak runs on its own private VM. The
Registry does not host stdio MCP servers.

The VM is created in `rg-mcp-registry`, has no public IP, and exposes only the
Registry HTTP front door on its private address to the edge subnet. The edge VM
remains responsible for public TLS termination and APISIX routing.

## Runtime secrets

The VM's system-assigned identity reads only these individually scoped platform
Key Vault secrets:

- `registry-secret-key`
- `auth-server-nginx-marker-secret`
- `mongodb-connection-string`
- `embeddings-api-key`
- `keycloak-client-secret`
- `keycloak-m2m-client-secret`
- `openbao-registry-token` (restricted OpenBao token for the Registry egress vault)
- `platform-ca-cert` (the CA that signs the private OpenBao listener certificate)

The existing secret-sync service writes protected raw files, and
`platform-apps-render` atomically generates the Registry and auth-server dotenv
files. The OpenBao token remains a protected raw file and is mounted directly
into the Registry container as a file-backed Compose secret rather than rendered
into an environment file. No secret values belong in Bicep, Compose, or
cloud-init.

## ACA rollback application images

The ACA tier consumes immutable image references in the form:

```text
<acr-login-server>/<repository>@sha256:<digest>
```

The previously inventoried ACR is `cr4bqvj62ztmxmi.azurecr.io` in
`rg-ai-access`. It did not contain the three required application images during
the read-only inventory, so publishing them remains an explicit operator
action.

## Required ACA rollback images

| Repository | Source Dockerfile | Build context |
| --- | --- | --- |
| `registry` | `docker/Dockerfile.registry` | repository root |
| `auth-server` | `docker/Dockerfile.auth` | repository root |
| `mcpgw` | `docker/Dockerfile.mcp-server` | repository root |

Build for the ACA worker architecture and tag with the source revision. Do not
use `latest` in the Bicep parameter file:

```bash
export ACR_LOGIN_SERVER='cr4bqvj62ztmxmi.azurecr.io'
export IMAGE_REVISION="$(git rev-parse --short=12 HEAD)"

docker build --platform linux/amd64 \
  --build-arg BUILD_VERSION="$IMAGE_REVISION" \
  -f docker/Dockerfile.registry \
  -t "$ACR_LOGIN_SERVER/registry:$IMAGE_REVISION" .

docker build --platform linux/amd64 \
  --build-arg BUILD_VERSION="$IMAGE_REVISION" \
  -f docker/Dockerfile.auth \
  -t "$ACR_LOGIN_SERVER/auth-server:$IMAGE_REVISION" .

docker build --platform linux/amd64 \
  -f docker/Dockerfile.mcp-server \
  -t "$ACR_LOGIN_SERVER/mcpgw:$IMAGE_REVISION" .

```

Publishing requires a separate approval because it changes the existing ACR:

```bash
az acr login --name cr4bqvj62ztmxmi
docker push "$ACR_LOGIN_SERVER/registry:$IMAGE_REVISION"
docker push "$ACR_LOGIN_SERVER/auth-server:$IMAGE_REVISION"
docker push "$ACR_LOGIN_SERVER/mcpgw:$IMAGE_REVISION"
```

After publishing, resolve each tag to its registry digest and place only the
digest references in the ACA rollback parameter file. Treat the digest list as
a release artifact; do not silently replace a digest with a mutable tag. The
active Keycloak VM does not use this ACR image; it pulls the official Quay
image by digest.

For example, retrieve a digest without exposing credentials:

```bash
az acr manifest show-metadata \
  --registry cr4bqvj62ztmxmi \
  --name "registry:$IMAGE_REVISION" \
  --query digest \
  --output tsv
```

The Keycloak VM uses the official `quay.io/keycloak/keycloak` image directly,
pinned by digest in the VM parameter file. Its database host, database name,
username, and password secret must be reviewed separately from the image
publication. The ACA rollback module continues to use its existing ACR image
contract until that rollback path is retired.
