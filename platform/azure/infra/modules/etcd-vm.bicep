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
  '    {"name": "grafana-otlp-etcd", "path": "/etc/platform/secrets/grafana-otlp"},'
  '    {"name": "etcd-server-cert", "path": "/etc/platform/tls/etcd-server.crt"},'
  '    {"name": "etcd-server-key", "path": "/etc/platform/tls/etcd-server.key"},'
  '    {"name": "etcd-health-client-cert", "path": "/etc/platform/tls/etcd-client.crt"},'
  '    {"name": "etcd-health-client-key", "path": "/etc/platform/tls/etcd-client.key"},'
  '    {"name": "platform-ca-cert", "path": "/etc/platform/tls/platform-ca.crt"}'
], '\n')

var secretNames = [
  'grafana-otlp-etcd'
  'etcd-server-cert'
  'etcd-server-key'
  'etcd-health-client-cert'
  'etcd-health-client-key'
  'platform-ca-cert'
]

var roleBootstrap = replace(
  replace(
    loadTextContent('../../scripts/bootstrap/platform-etcd-files.sh'),
    '__PLATFORM_ETCD_COMPOSE_CONTENT__',
    loadTextContent('../../config/etcd/compose.yaml')
  ),
  '__PLATFORM_ETCD_UNIT__',
  loadTextContent('../../scripts/systemd/platform-etcd.service')
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
              'etcd'
            ),
            '__PLATFORM_FORMAT_DATA_DISK__',
            'true'
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
  name: 'etcd-linux-vm'
  params: {
    location: location
    vmName: vmName
    vmSize: vmSize
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    subnetId: subnetId
    privateIpAddress: privateIpAddress
    dataDiskSizeGb: 32
    customData: customData
    tags: tags
  }
}

module secretAccess './key-vault-secret-role.bicep' = [for secretName in secretNames: if (deployRuntimeAccess) {
  name: 'etcd-${secretName}-secret-access'
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
output dataDiskId string = vm.outputs.dataDiskId
