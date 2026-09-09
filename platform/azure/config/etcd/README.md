# etcd runtime configuration

This Compose file is the single-node Azure pilot configuration for the etcd VM. It is intentionally not the same as the local `docker-compose.edge.yml` profile.

The service exposes only the mTLS-protected client endpoint on the static private address `10.60.2.4:2379`. Peer port `2380` is bound only to the container loopback interface and is not published on the VM.

The following files must be rendered by the protected secret-sync workflow before the service unit is enabled. The systemd unit also requires the secret-sync service and fails closed if synchronization fails:

```text
/etc/platform/tls/platform-ca.crt
/etc/platform/tls/etcd-server.crt
/etc/platform/tls/etcd-server.key
/etc/platform/tls/etcd-client.crt
/etc/platform/tls/etcd-client.key
```

The etcd data directory is `/var/lib/platform/data/etcd`. The image is pinned by digest and the container uses a read-only root filesystem.
