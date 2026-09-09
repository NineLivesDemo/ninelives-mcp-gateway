@description('Azure region for the Keycloak VM.')
param location string

@description('Keycloak VM resource name.')
param vmName string

@description('Keycloak VM size.')
param vmSize string

@description('Linux administrator username.')
param adminUsername string

@description('SSH public key. Password authentication is disabled.')
@secure()
param adminPublicKey string

@description('Keycloak subnet resource ID.')
param subnetId string

@description('Static private IPv4 address.')
param privateIpAddress string

@description('Platform Key Vault URI used by the VM secret synchronizer.')
param keyVaultUri string

@description('Platform Key Vault name.')
param keyVaultName string

@description('Resource group containing the platform Key Vault.')
param keyVaultResourceGroupName string

@description('Pinned official Keycloak image reference.')
@minLength(1)
param keycloakImage string

@description('Public Keycloak hostname used for issuer and redirect URLs.')
@minLength(3)
param keycloakHostname string

@description('Existing Keycloak PostgreSQL host.')
@minLength(1)
param keycloakDbHost string

@description('Keycloak PostgreSQL database name.')
param keycloakDbName string = 'keycloak'

@description('Keycloak PostgreSQL username.')
param keycloakDbUsername string = 'keycloak'

@description('Whether to create the VM identity secret role assignments.')
param deployRuntimeAccess bool = false

@description('Key Vault secret name containing the Keycloak administrator password.')
param keycloakAdminPasswordSecretName string = 'keycloak-admin-password'

@description('Key Vault secret name containing the Keycloak database password.')
param keycloakDbPasswordSecretName string = 'keycloak-db-password'

@description('Tags applied to the VM and identity.')
param tags object = {}

var secretMappings = join([
  '    {"name": "${keycloakAdminPasswordSecretName}", "path": "/etc/platform/secrets/raw/keycloak-admin-password"},'
  '    {"name": "${keycloakDbPasswordSecretName}", "path": "/etc/platform/secrets/raw/keycloak-db-password"}'
], '\n')

var secretNames = [
  keycloakAdminPasswordSecretName
  keycloakDbPasswordSecretName
]

var keycloakComposeImage = replace(
  loadTextContent('../../config/keycloak/compose.yaml'),
  '__PLATFORM_KEYCLOAK_IMAGE__',
  keycloakImage
)
var keycloakComposeIp = replace(
  keycloakComposeImage,
  '__PLATFORM_KEYCLOAK_PRIVATE_IP__',
  privateIpAddress
)
var keycloakComposeHostname = replace(
  keycloakComposeIp,
  '__PLATFORM_KEYCLOAK_HOSTNAME__',
  keycloakHostname
)
var keycloakComposeDbHost = replace(
  keycloakComposeHostname,
  '__PLATFORM_KEYCLOAK_DB_HOST__',
  keycloakDbHost
)
var keycloakComposeDbName = replace(
  keycloakComposeDbHost,
  '__PLATFORM_KEYCLOAK_DB_NAME__',
  keycloakDbName
)
var keycloakCompose = replace(
  keycloakComposeDbName,
  '__PLATFORM_KEYCLOAK_DB_USERNAME__',
  keycloakDbUsername
)

var roleBootstrapBase = replace(
  loadTextContent('../../scripts/bootstrap/platform-keycloak-files.sh'),
  '__PLATFORM_KEYCLOAK_COMPOSE_CONTENT__',
  keycloakCompose
)
var roleBootstrapRenderer = replace(
  roleBootstrapBase,
  '__PLATFORM_KEYCLOAK_RENDER_CONTENT__',
  loadTextContent('../../scripts/bootstrap/platform-keycloak-render.py')
)
var roleBootstrapEnv = replace(
  roleBootstrapRenderer,
  '__PLATFORM_KEYCLOAK_ENV_UNIT__',
  loadTextContent('../../scripts/systemd/platform-keycloak-env.service')
)
var roleBootstrap = replace(
  roleBootstrapEnv,
  '__PLATFORM_KEYCLOAK_UNIT__',
  loadTextContent('../../scripts/systemd/platform-keycloak.service')
)

var customData = replace(
  replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              loadTextContent('../../scripts/bootstrap/host-bootstrap.sh'),
              '__PLATFORM_ROLE__',
              'keycloak'
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
)

var customDataWithRole = replace(
  customData,
  '__PLATFORM_ROLE_BOOTSTRAP__',
  roleBootstrap
)

module vm './linux-vm.bicep' = {
  name: 'keycloak-linux-vm'
  params: {
    location: location
    vmName: vmName
    vmSize: vmSize
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    subnetId: subnetId
    privateIpAddress: privateIpAddress
    customData: customDataWithRole
    tags: tags
  }
}

module secretAccess './key-vault-secret-role.bicep' = [
  for secretName in secretNames: if (deployRuntimeAccess) {
    name: 'keycloak-${secretName}-secret-access'
    scope: resourceGroup(keyVaultResourceGroupName)
    params: {
      keyVaultName: keyVaultName
      secretName: secretName
      principalId: vm.outputs.principalId
    }
  }
]

output vmId string = vm.outputs.vmId
output principalId string = vm.outputs.principalId
output privateIpAddress string = vm.outputs.privateIpAddress
