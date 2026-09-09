# Keycloak VM

The Keycloak VM runs the official Keycloak image pinned by digest with the
existing managed PostgreSQL database. It has no public IP and exposes HTTP port
8080 only to the edge subnet, the Registry application subnet, and the approved
management subnet. The edge proxy terminates public TLS and forwards to the
private HTTP listener.

The VM reads only `keycloak-admin-password` and `keycloak-db-password` from the
platform Key Vault. The secret synchronizer writes raw values under
`/etc/platform/secrets/raw`, and `platform-keycloak-render` atomically creates
the protected Compose dotenv file.

Keycloak realm and client initialization remains an operator action performed
with `keycloak/setup/init-keycloak.sh`. The VM does not create or migrate the
database.
