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
param azureTenantId string
param deployRuntimeAccess bool = false
param tags object = {}

var secretMappings = join([
  '    {"name": "grafana-otlp-openbao", "path": "/etc/platform/secrets/grafana-otlp"},'
  '    {"name": "openbao-tls-cert", "path": "/etc/platform/tls/openbao.crt"},'
  '    {"name": "openbao-tls-key", "path": "/etc/platform/tls/openbao.key"},'
  '    {"name": "platform-ca-cert", "path": "/etc/platform/tls/platform-ca.crt"}'
], '\n')

var secretNames = [
  'grafana-otlp-openbao'
  'openbao-tls-cert'
  'openbao-tls-key'
  'platform-ca-cert'
]

var openBaoHcl = replace(
  replace(
    loadTextContent('../../config/openbao/openbao.hcl'),
    '__AZURE_TENANT_ID__',
    azureTenantId
  ),
  '__PLATFORM_KEY_VAULT_NAME__',
  keyVaultName
)

var openBaoEnv = join([
  'AZURE_TENANT_ID=${azureTenantId}'
  'VAULT_AZUREKEYVAULT_VAULT_NAME=${keyVaultName}'
  'VAULT_AZUREKEYVAULT_KEY_NAME=openbao-unseal'
], '\n')

var roleBootstrap = replace(
  replace(
    replace(
      replace(
        loadTextContent('../../scripts/bootstrap/platform-openbao-files.sh'),
        '__PLATFORM_OPENBAO_COMPOSE_CONTENT__',
        loadTextContent('../../config/openbao/compose.yaml')
      ),
      '__PLATFORM_OPENBAO_HCL_CONTENT__',
      openBaoHcl
    ),
    '__PLATFORM_OPENBAO_ENV_CONTENT__',
    openBaoEnv
  ),
  '__PLATFORM_OPENBAO_UNIT__',
  loadTextContent('../../scripts/systemd/platform-openbao.service')
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
              'openbao'
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
  name: 'openbao-linux-vm'
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
  name: 'openbao-${secretName}-secret-access'
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
