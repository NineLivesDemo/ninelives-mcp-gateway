@description('Azure region for the application VM.')
param location string

@description('Application VM resource name.')
param vmName string

@description('Application VM size.')
param vmSize string

@description('Linux administrator username.')
param adminUsername string

@description('SSH public key. Password authentication is disabled.')
@secure()
param adminPublicKey string

@description('Application subnet resource ID.')
param subnetId string

@description('Static private IPv4 address.')
param privateIpAddress string

@description('Platform Key Vault URI used by the VM secret synchronizer.')
param keyVaultUri string

@description('Platform Key Vault name.')
param keyVaultName string

@description('Resource group containing the platform Key Vault.')
param keyVaultResourceGroupName string

@description('Existing ACR name containing immutable application images.')
param acrName string

@description('Resource group containing the existing ACR.')
param acrResourceGroupName string

@description('Immutable Registry image reference.')
@minLength(1)
param registryImage string

@description('Immutable auth-server image reference.')
@minLength(1)
param authServerImage string

@description('Immutable MCP gateway image reference.')
@minLength(1)
param mcpgwImage string

@description('Public Registry hostname used for browser-facing URLs.')
@minLength(3)
param registryHostname string

@description('Internal Keycloak URL used by the application containers.')
@minLength(8)
param keycloakUrl string

@description('External Keycloak URL used for issuer and redirect URLs.')
@minLength(8)
param keycloakExternalUrl string

@description('Whether to create the VM identity secret role assignments.')
param deployRuntimeAccess bool = false

@description('Whether to install the UV-managed Python 3.10 compatibility runtime for the legacy Hybrid Worker handler.')
param enablePython310Compat bool = false

@description('Key Vault secret name containing the Registry signing secret.')
param registrySecretKeyName string = 'registry-secret-key'

@description('Key Vault secret name shared by Registry and auth-server for NGINX markers.')
param authServerMarkerSecretName string = 'auth-server-nginx-marker-secret'

@description('Key Vault secret name containing the MongoDB connection string.')
param mongodbConnectionStringSecretName string = 'mongodb-connection-string'

@description('Key Vault secret name containing the embeddings API key.')
param embeddingsApiKeySecretName string = 'embeddings-api-key'

@description('Key Vault secret name containing the Keycloak web client secret.')
param keycloakClientSecretName string = 'keycloak-client-secret'

@description('Key Vault secret name containing the Keycloak M2M client secret.')
param keycloakM2mClientSecretName string = 'keycloak-m2m-client-secret'

@description('Key Vault secret name containing the restricted Registry OpenBao token.')
param openBaoRegistryTokenSecretName string = 'openbao-registry-token'

@description('Tags applied to the VM and identity.')
param tags object = {}

var registryExternalUrl = 'https://${registryHostname}'
var secretMappings = join([
  '    {"name": "${registrySecretKeyName}", "path": "/etc/platform/secrets/raw/registry-secret-key"},'
  '    {"name": "${authServerMarkerSecretName}", "path": "/etc/platform/secrets/raw/auth-server-nginx-marker-secret"},'
  '    {"name": "${mongodbConnectionStringSecretName}", "path": "/etc/platform/secrets/raw/mongodb-connection-string"},'
  '    {"name": "${embeddingsApiKeySecretName}", "path": "/etc/platform/secrets/raw/embeddings-api-key"},'
  '    {"name": "${keycloakClientSecretName}", "path": "/etc/platform/secrets/raw/keycloak-client-secret"},'
  '    {"name": "${keycloakM2mClientSecretName}", "path": "/etc/platform/secrets/raw/keycloak-m2m-client-secret"},'
  '    {"name": "${openBaoRegistryTokenSecretName}", "path": "/etc/platform/secrets/raw/openbao-registry-token"},'
  '    {"name": "platform-ca-cert", "path": "/etc/platform/tls/platform-ca.crt"}'
], '\n')

var secretNames = [
  registrySecretKeyName
  authServerMarkerSecretName
  mongodbConnectionStringSecretName
  embeddingsApiKeySecretName
  keycloakClientSecretName
  keycloakM2mClientSecretName
  openBaoRegistryTokenSecretName
  'platform-ca-cert'
]

var appsComposeRegistryImage = replace(
  loadTextContent('../../config/apps/compose.yaml'),
  '__PLATFORM_REGISTRY_IMAGE__',
  registryImage
)
var appsComposeAuthServerImage = replace(
  appsComposeRegistryImage,
  '__PLATFORM_AUTH_SERVER_IMAGE__',
  authServerImage
)
var appsComposeMcpgwImage = replace(
  appsComposeAuthServerImage,
  '__PLATFORM_MCPGW_IMAGE__',
  mcpgwImage
)
var appsComposePrivateIp = replace(
  appsComposeMcpgwImage,
  '__PLATFORM_APP_PRIVATE_IP__',
  privateIpAddress
)
var appsComposeRegistryUrl = replace(
  appsComposePrivateIp,
  '__PLATFORM_REGISTRY_EXTERNAL_URL__',
  registryExternalUrl
)
var appsCompose = replace(
  appsComposeRegistryUrl,
  '__PLATFORM_REGISTRY_HOSTNAME__',
  registryHostname
)
var roleBootstrapBase = replace(
  loadTextContent('../../scripts/bootstrap/platform-apps-files.sh'),
  '__PLATFORM_APPS_COMPOSE_CONTENT__',
  appsCompose
)
var roleBootstrapKeycloakUrl = replace(
  roleBootstrapBase,
  '__PLATFORM_KEYCLOAK_URL__',
  keycloakUrl
)
var roleBootstrapKeycloakExternalUrl = replace(
  roleBootstrapKeycloakUrl,
  '__PLATFORM_KEYCLOAK_EXTERNAL_URL__',
  keycloakExternalUrl
)
var roleBootstrapRender = replace(
  roleBootstrapKeycloakExternalUrl,
  '__PLATFORM_APPS_RENDER_CONTENT__',
  loadTextContent('../../scripts/bootstrap/platform-apps-render.py')
)
var roleBootstrap = replace(
  roleBootstrapRender,
  '__PLATFORM_APPS_ENV_UNIT__',
  loadTextContent('../../scripts/systemd/platform-apps-env.service')
)

var roleBootstrapComplete = replace(
  roleBootstrap,
  '__PLATFORM_APPS_UNIT__',
  loadTextContent('../../scripts/systemd/platform-apps.service')
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
              'apps'
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

var customDataWithPython310CompatFlag = replace(
  customData,
  '__PLATFORM_ENABLE_PYTHON310_COMPAT__',
  string(enablePython310Compat)
)

var customDataWithPython310Compat = replace(
  customDataWithPython310CompatFlag,
  '__PLATFORM_PYTHON310_COMPAT_CONTENT__',
  loadTextContent('../../scripts/bootstrap/install-python310-compat.sh')
)
var customDataWithAcrName = replace(
  customDataWithPython310Compat,
  '__PLATFORM_ACR_NAME__',
  acrName
)

var customDataWithRole = replace(
  customDataWithAcrName,
  '__PLATFORM_ROLE_BOOTSTRAP__',
  roleBootstrapComplete
)

module vm './linux-vm.bicep' = {
  name: 'apps-linux-vm'
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

module acrPullRole './acr-pull-role.bicep' = {
  name: 'apps-acr-pull'
  scope: resourceGroup(acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: vm.outputs.principalId
  }
}

module secretAccess './key-vault-secret-role.bicep' = [
  for secretName in secretNames: if (deployRuntimeAccess) {
    name: 'apps-${secretName}-secret-access'
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
