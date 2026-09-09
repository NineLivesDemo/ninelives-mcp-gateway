# Azure OAuth Routing Postmortem

## Summary

The Azure OAuth incident was not one failure. Three independent defects affected
the Registry request path at different stages:

1. Registry Nginx did not send TLS SNI when proxying to the HTTPS auth-server
   Container App.
2. The Nginx `auth_request` subrequest used unsafe proxy defaults and forwarded
   request state that ACA could reject before the auth-server application ran.
3. The shared Nginx marker secret contained a trailing newline, which was
   rendered into an upstream HTTP header and caused ACA to return `400` before
   Uvicorn received `/validate`.

The first issue broke the OAuth redirect flow. The latter two affected the
authenticated Registry API path, especially `/api/auth/me`.

## Architecture and impact

The affected path is:

```text
Browser
  -> Cloudflare Tunnel
  -> APISIX on the edge VM
  -> Registry ACA ingress
  -> Registry Nginx
  -> auth-server ACA ingress
  -> auth-server /validate
  -> Registry FastAPI endpoint
```

The auth-server ACA ingress is intentionally public at the ACA resource level.
It is not the browser-facing endpoint: traffic is constrained by the deployment
topology and is reached through the Registry/edge path described in
`platform/azure/README.md`.

Observed symptoms were:

- OAuth authorization requests returned an upstream `404` before the
  auth-server application received the request.
- `/api/auth/me` returned `500` from Nginx.
- Nginx logged `auth request unexpected status: 400`.
- Auth-server application logs showed no corresponding `/validate` request,
  proving that the rejection occurred before Uvicorn.

## Issue 1: Missing TLS SNI to the auth-server ACA ingress

### Root cause

Registry Nginx proxied HTTPS to the auth-server ACA hostname without enabling
SNI. ACA selected the wrong ingress route during the TLS request, so the
upstream returned `404` before the auth-server application was reached.

### Fix

The Nginx renderer now emits fail-closed auth-server TLS settings:

- `proxy_ssl_server_name on`
- `proxy_ssl_name` set to the parsed auth-server hostname
- certificate verification enabled
- the configured CA bundle and hostname used for verification

### Verification

The public OAuth login endpoint returned `302` with the expected Keycloak
authorization parameters after this change.

## Issue 2: Unsafe `auth_request` proxy defaults

### Root cause

The internal Nginx `/validate` subrequest inherited defaults that were not
appropriate for ACA ingress:

- the upstream request could use HTTP/1.0, which ACA rejected with `426 Upgrade
  Required`;
- the request body and framing headers were unnecessary for a bodyless
  validation request;
- forwarding the complete public request header set allowed Cloudflare/APISIX
  headers and client-controlled metadata to reach ACA ingress.

These failures occurred before the auth-server application, which explained
the absence of `/validate` entries in Uvicorn logs.

### Fix

The `/validate` location now:

- uses `proxy_http_version 1.1`;
- disables request-body forwarding;
- clears `Content-Length` and `Connection`;
- disables inherited request-header forwarding;
- forwards only the explicit credentials and request metadata consumed by
  auth-server;
- overwrites client source headers with Nginx-derived values.

The change was applied consistently to both Nginx templates:

- `docker/nginx_rev_proxy_http_only.conf`
- `docker/nginx_rev_proxy_http_and_https.conf`

### Verification

The targeted Nginx regression suite passed with 122 tests after the
subrequest changes. ACA continued to return `400`, however, which led to the
third root cause below.

## Issue 3: Trailing newline in the shared marker secret

### Root cause

The `AUTH_SERVER_NGINX_MARKER_SECRET` value came from deployment secret
material that included a trailing newline. Registry Nginx inserted the raw
environment value into the generated configuration. The deployed configuration
therefore contained the marker header across two physical lines:

```nginx
proxy_set_header X-Validate-Source-Secret "…secret…
";
```

The resulting malformed upstream header was rejected by ACA with `400` before
auth-server received the request. Direct curl probes did not reproduce the
failure because they did not include the malformed marker header.

### Fix

The shared signing-secret validator is now used for
`AUTH_SERVER_NGINX_MARKER_SECRET` during settings initialization. It rejects
missing and weak values and returns the value with surrounding whitespace
stripped. Nginx consumes the validated settings value rather than reading the
raw environment variable during template rendering. The existing Nginx
sanitizer remains a defense-in-depth boundary for generated quoted values.

Regression coverage verifies that a marker secret ending in `\n` is normalized
before it can reach auth-server or generated Nginx configuration.

## Why diagnosis took multiple iterations

The defects were layered:

- fixing SNI made OAuth authorization reachable but did not exercise the
  authenticated API validation path;
- fixing HTTP version, headers, and request-body behavior removed known ACA
  ingress incompatibilities but did not remove the malformed marker value;
- direct auth-server requests returned ordinary `401` responses, which showed
  that the application itself handled validation correctly but did not reproduce
  the exact Nginx-generated request.

The decisive evidence was the live generated Nginx configuration together with
the pair of observations that Nginx received `400` and Uvicorn logged no
`/validate` request.

## Preventive controls

- Validate every secret before using it in generated configuration.
- Never render raw environment values into Nginx directives.
- Keep auth subrequests bodyless and use an explicit header allowlist.
- Capture generated Nginx configuration in deployment diagnostics without
  exposing secret values.
- Verify each proxy hop independently: edge access log, Registry Nginx error
  log, auth-server application log, and final FastAPI response.
- Keep the ACA image references immutable by digest as required by
  `platform/azure/config/apps/README.md`.

## Validation and deployment record

The marker normalization change passed 252 focused tests covering settings,
secret validation, and Nginx rendering. The Registry image was built and
published to the existing ACR with digest:

```text
sha256:266292e1bb053df40ab59a6ee4408c7e1d2254c908b9df8fc417e644c276b394
```

The preceding bodyless-subrequest revision was healthy and carried 100% of
traffic during diagnosis. The marker-normalization image is the release
artifact for the next Registry ACA revision; after rollout, verify that
unauthenticated `/api/auth/me` returns `401`, authenticated `/api/auth/me`
returns the user/permission payload, and OAuth login remains `302`.
