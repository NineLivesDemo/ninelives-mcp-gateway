param location string
param vmName string
param vmSize string
param adminUsername string
@secure()
param adminPublicKey string
param subnetId string
param privateIpAddress string
param keyVaultUri string
param keyVaultName string
param keyVaultResourceGroupName string
param deployRuntimeAccess bool = false
param tags object = {}

var secretMappings = join([
  '    {"name": "cloudflare-tunnel-token", "path": "/etc/platform/secrets/cloudflare-tunnel-token"},'
  '    {"name": "apisix-admin-key", "path": "/etc/platform/secrets/apisix-admin-key"},'
  '    {"name": "grafana-otlp-edge", "path": "/etc/platform/secrets/grafana-otlp"},'
  '    {"name": "etcd-edge-client-cert", "path": "/etc/platform/tls/etcd-client.crt"},'
  '    {"name": "etcd-edge-client-key", "path": "/etc/platform/tls/etcd-client.key"},'
  '    {"name": "platform-ca-cert", "path": "/etc/platform/tls/platform-ca.crt"}'
], '\n')

var secretNames = [
  'cloudflare-tunnel-token'
  'apisix-admin-key'
  'grafana-otlp-edge'
  'etcd-edge-client-cert'
  'etcd-edge-client-key'
  'platform-ca-cert'
]

var roleBootstrapStage1 = replace(
  replace(
    replace(
      loadTextContent('../../scripts/bootstrap/platform-edge-files.sh'),
      '__PLATFORM_EDGE_COMPOSE_CONTENT__',
      loadTextContent('../../config/edge/compose.yaml')
    ),
    '__PLATFORM_EDGE_APISIX_CONTENT__',
    loadTextContent('../../config/edge/apisix.yaml')
  ),
  '__PLATFORM_EDGE_ROUTE_CONTENT__',
  loadTextContent('../../config/edge/registry-route.template.json')
)

var roleBootstrapStage2 = replace(
  replace(
    replace(
      replace(
        roleBootstrapStage1,
        '__PLATFORM_KEYCLOAK_ROUTE_CONTENT__',
        loadTextContent('../../config/edge/keycloak-route.template.json')
      ),
      '__PLATFORM_EDGE_ORIGIN_CONTENT__',
      loadTextContent('../../config/edge/edge-origin.env.example')
    ),
    '__PLATFORM_EDGE_RENDER_CONTENT__',
    loadTextContent('../../scripts/bootstrap/platform-edge-render.py')
  ),
  '__PLATFORM_EDGE_BOOTSTRAP_CONTENT__',
  loadTextContent('../../scripts/bootstrap/platform-edge-bootstrap.sh')
)

var roleBootstrap = replace(
  replace(
    roleBootstrapStage2,
    '__PLATFORM_EDGE_ENV_UNIT__',
    loadTextContent('../../scripts/systemd/platform-edge-env.service')
  ),
  '__PLATFORM_EDGE_UNIT__',
  loadTextContent('../../scripts/systemd/platform-edge.service')
)

var customData = replace(
  replace(
  replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              loadTextContent('../../scripts/bootstrap/host-bootstrap.sh'),
              '__PLATFORM_ROLE__',
              'edge'
            ),
            '__PLATFORM_FORMAT_DATA_DISK__',
            'false'
          ),
          '__PLATFORM_SECRET_SYNC_CONTENT__',
          loadTextContent('../../scripts/secret-sync/platform-secret-sync.py')
        ),
        '__PLATFORM_KEY_VAULT_URI__',
        keyVaultUri
      ),
      '__PLATFORM_SECRET_MAPPINGS__',
      secretMappings
    ),
    '__PLATFORM_SECRET_SYNC_UNIT__',
    loadTextContent('../../scripts/systemd/platform-secret-sync.service')
  ),
  '__PLATFORM_SECRET_SYNC_TIMER__',
  loadTextContent('../../scripts/systemd/platform-secret-sync.timer')
  ),
  '__PLATFORM_ROLE_BOOTSTRAP__',
  roleBootstrap
)

module vm './linux-vm.bicep' = {
  name: 'edge-linux-vm'
  params: {
    location: location
    vmName: vmName
    vmSize: vmSize
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    subnetId: subnetId
    privateIpAddress: privateIpAddress
    customData: customData
    tags: tags
  }
}

module secretAccess './key-vault-secret-role.bicep' = [for secretName in secretNames: if (deployRuntimeAccess) {
  name: 'edge-${secretName}-secret-access'
  scope: resourceGroup(keyVaultResourceGroupName)
  params: {
    keyVaultName: keyVaultName
    secretName: secretName
    principalId: vm.outputs.principalId
  }
}]

output vmId string = vm.outputs.vmId
output principalId string = vm.outputs.principalId
output privateIpAddress string = vm.outputs.privateIpAddress
