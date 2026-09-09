targetScope = 'subscription'

@description('Reusable platform environment identifier.')
param environmentName string = 'platform-pilot'

@description('Azure region for the platform foundation.')
param location string = 'westus3'

@description('Private address space reserved for the platform VNet.')
param vnetAddressPrefix string = '10.60.0.0/16'

@description('Linux administrator username. Password authentication is disabled.')
param adminUsername string = 'platformadmin'

@description('SSH public key for emergency VM access through approved private management paths.')
@secure()
param adminPublicKey string

@description('Edge VM size.')
param edgeVmSize string = 'Standard_D2ls_v7'

@description('etcd VM size.')
param etcdVmSize string = 'Standard_D2ls_v7'

@description('OpenBao VM size.')
param openBaoVmSize string = 'Standard_D2ls_v7'

@description('Whether to provision the existing edge, etcd, and OpenBao VMs.')
param deployFoundationVms bool = false

@description('Whether to deploy the private Registry application VM.')
param deployAppVm bool = false

@description('Registry application VM size.')
param appVmSize string = 'Standard_E2ds_v7'

@description('Private address for the Registry application VM.')
param appVmPrivateIpAddress string = '10.60.4.4'

@description('Whether to deploy the private Keycloak VM.')
param deployKeycloakVm bool = false

@description('Whether to deploy Azure Bastion for private VM access.')
param deployBastion bool = false

@description('Keycloak VM size.')
param keycloakVmSize string = 'Standard_E2ds_v7'

@description('Private address for the Keycloak VM.')
param keycloakVmPrivateIpAddress string = '10.60.5.4'

@description('Whether to deploy per-secret Key Vault access for the VM identities.')
param deployRuntimeAccess bool = false

@description('Whether to deploy the private Container Apps application tier.')
param deployApps bool = false

@description('Existing ACR name used by the application tier.')
param appsAcrName string = ''

@description('Resource group containing the existing ACR.')
param appsAcrResourceGroupName string = ''

@description('Existing Log Analytics workspace used by the application tier.')
param appsLogAnalyticsWorkspaceName string = ''

@description('Resource group containing the Log Analytics workspace.')
param appsLogAnalyticsWorkspaceResourceGroupName string = ''

@description('Existing application Key Vault name.')
param appsKeyVaultName string = ''

@description('Resource group containing the application Key Vault.')
param appsKeyVaultResourceGroupName string = ''

@description('Private Registry hostname used for application redirects.')
param registryHostname string = ''

@description('Private Keycloak hostname used for application redirects.')
param keycloakHostname string = ''

@description('Internal URL used by the Registry application VM to reach Keycloak.')
param keycloakUrl string = ''

@description('External Keycloak URL used in issuer metadata and browser redirects.')
param keycloakExternalUrl string = ''

@description('Immutable Registry image reference.')
param registryImage string = ''

@description('Immutable auth-server image reference.')
param authServerImage string = ''

@description('Immutable MCP gateway image reference.')
param mcpgwImage string = ''

@description('Immutable Keycloak image reference.')
param keycloakImage string = ''

@description('Keycloak PostgreSQL host.')
param keycloakDbHost string = ''

@description('Existing Keycloak PostgreSQL Flexible Server name.')
param keycloakDbServerName string = ''

@description('Resource group containing the existing Keycloak PostgreSQL Flexible Server.')
param keycloakDbResourceGroupName string = ''

@description('Keycloak PostgreSQL database name.')
param keycloakDbName string = 'keycloak'

@description('Keycloak PostgreSQL username.')
param keycloakDbUsername string = 'keycloak'

@description('Key Vault secret name containing the Keycloak web client secret.')
param keycloakClientSecretName string = 'keycloak-client-secret'

@description('Key Vault secret name containing the Keycloak M2M client secret.')
param keycloakM2mClientSecretName string = 'keycloak-m2m-client-secret'

@description('Key Vault secret name containing the restricted Registry OpenBao token.')
param openBaoRegistryTokenSecretName string = 'openbao-registry-token'

@description('Key Vault secret name containing the Keycloak administrator password.')
param keycloakAdminPasswordSecretName string = 'keycloak-admin-password'

@description('Key Vault secret name containing the Keycloak database password.')
param keycloakDbPasswordSecretName string = 'keycloak-db-password'

@description('Create a private endpoint for the existing Keycloak PostgreSQL server.')
param deployKeycloakDbPrivateEndpoint bool = false

@description('Tags applied to platform resources.')
param tags object = {
  environment: environmentName
  managedBy: 'bicep'
  platform: 'shared'
  workload: 'platform-foundation'
}

var networkResourceGroupName = 'rg-network'
var edgeResourceGroupName = 'rg-edge'
var etcdResourceGroupName = 'rg-etcd'
var openBaoResourceGroupName = 'rg-openbao'
var appsResourceGroupName = 'rg-apps'
var registryResourceGroupName = 'rg-mcp-registry'
var keycloakResourceGroupName = 'rg-mcp-keycloak'
var opsResourceGroupName = 'rg-ops'
var platformKeyVaultName = 'kvplatform${uniqueString(subscription().id)}'

resource existingEdgeVm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: 'vm-platform-edge'
  scope: edgeResourceGroup
}

resource existingEtcdVm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: 'vm-platform-etcd'
  scope: etcdResourceGroup
}

resource existingOpenBaoVm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: 'vm-platform-openbao'
  scope: openBaoResourceGroup
}

resource networkResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: networkResourceGroupName
  location: location
  tags: tags
}

resource edgeResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: edgeResourceGroupName
  location: location
  tags: tags
}

resource etcdResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: etcdResourceGroupName
  location: location
  tags: tags
}

resource openBaoResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: openBaoResourceGroupName
  location: location
  tags: tags
}

resource appsResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: appsResourceGroupName
  location: location
  tags: tags
}

resource registryResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: registryResourceGroupName
  location: location
  tags: union(tags, {
    workload: 'mcp-registry'
  })
}

resource keycloakResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: keycloakResourceGroupName
  location: location
  tags: union(tags, {
    workload: 'keycloak'
  })
}

resource opsResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: opsResourceGroupName
  location: location
  tags: tags
}

module network './modules/network.bicep' = {
  name: '${environmentName}-network'
  scope: networkResourceGroup
  params: {
    location: location
    vnetName: 'vnet-${environmentName}'
    vnetAddressPrefix: vnetAddressPrefix
    deployApplicationVm: deployAppVm
    deployKeycloakVm: deployKeycloakVm
    deployBastion: deployBastion
    tags: tags
  }
}

module ops './modules/ops.bicep' = {
  name: '${environmentName}-ops'
  scope: opsResourceGroup
  params: {
    location: location
    keyVaultName: platformKeyVaultName
    automationAccountName: 'aa-${environmentName}'
    tags: tags
  }
}

module edge './modules/edge-vm.bicep' = if (deployFoundationVms) {
  name: '${environmentName}-edge-vm'
  scope: edgeResourceGroup
  params: {
    location: location
    vmName: 'vm-platform-edge'
    vmSize: edgeVmSize
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    subnetId: network.outputs.edgeSubnetId
    privateIpAddress: '10.60.1.4'
    keyVaultUri: ops.outputs.keyVaultUri
    keyVaultName: ops.outputs.keyVaultName
    keyVaultResourceGroupName: opsResourceGroupName
    deployRuntimeAccess: deployRuntimeAccess
    tags: tags
  }
}

module etcd './modules/etcd-vm.bicep' = if (deployFoundationVms) {
  name: '${environmentName}-etcd-vm'
  scope: etcdResourceGroup
  params: {
    location: location
    vmName: 'vm-platform-etcd'
    vmSize: etcdVmSize
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    subnetId: network.outputs.etcdSubnetId
    privateIpAddress: '10.60.2.4'
    keyVaultUri: ops.outputs.keyVaultUri
    keyVaultName: ops.outputs.keyVaultName
    keyVaultResourceGroupName: opsResourceGroupName
    deployRuntimeAccess: deployRuntimeAccess
    tags: tags
  }
}

module openBao './modules/openbao-vm.bicep' = if (deployFoundationVms) {
  name: '${environmentName}-openbao-vm'
  scope: openBaoResourceGroup
  params: {
    location: location
    vmName: 'vm-platform-openbao'
    vmSize: openBaoVmSize
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    subnetId: network.outputs.openBaoSubnetId
    privateIpAddress: '10.60.3.4'
    keyVaultUri: ops.outputs.keyVaultUri
    keyVaultName: ops.outputs.keyVaultName
    keyVaultResourceGroupName: opsResourceGroupName
    azureTenantId: tenant().tenantId
    deployRuntimeAccess: deployRuntimeAccess
    tags: tags
  }
}

module openBaoAccess './modules/key-vault-access.bicep' = {
  name: '${environmentName}-openbao-key-vault-access'
  scope: opsResourceGroup
  params: {
    keyVaultName: ops.outputs.keyVaultName
    principalId: deployFoundationVms
      ? openBao.outputs.principalId
      : existingOpenBaoVm.identity.principalId
  }
}

module appVm './modules/application-vm.bicep' = if (deployAppVm) {
  name: '${environmentName}-application-vm'
  scope: registryResourceGroup
  params: {
    location: location
    vmName: 'vm-platform-apps'
    vmSize: appVmSize
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    subnetId: network.outputs.appsSubnetId
    privateIpAddress: appVmPrivateIpAddress
    keyVaultUri: ops.outputs.keyVaultUri
    keyVaultName: ops.outputs.keyVaultName
    keyVaultResourceGroupName: opsResourceGroupName
    acrName: appsAcrName
    acrResourceGroupName: appsAcrResourceGroupName
    registryImage: registryImage
    authServerImage: authServerImage
    mcpgwImage: mcpgwImage
    registryHostname: registryHostname
    keycloakUrl: keycloakUrl
    keycloakExternalUrl: keycloakExternalUrl
    openBaoRegistryTokenSecretName: openBaoRegistryTokenSecretName
    deployRuntimeAccess: deployRuntimeAccess
    tags: tags
  }
}

module keycloakVm './modules/keycloak-vm.bicep' = if (deployKeycloakVm) {
  name: '${environmentName}-keycloak-vm'
  scope: keycloakResourceGroup
  params: {
    location: location
    vmName: 'vm-platform-keycloak'
    vmSize: keycloakVmSize
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    subnetId: network.outputs.keycloakSubnetId
    privateIpAddress: keycloakVmPrivateIpAddress
    keyVaultUri: ops.outputs.keyVaultUri
    keyVaultName: ops.outputs.keyVaultName
    keyVaultResourceGroupName: opsResourceGroupName
    keycloakImage: keycloakImage
    keycloakHostname: keycloakHostname
    keycloakDbHost: keycloakDbHost
    keycloakDbName: keycloakDbName
    keycloakDbUsername: keycloakDbUsername
    deployRuntimeAccess: deployRuntimeAccess
    keycloakAdminPasswordSecretName: keycloakAdminPasswordSecretName
    keycloakDbPasswordSecretName: keycloakDbPasswordSecretName
    tags: tags
  }
}

module apps './modules/aca-apps.bicep' = if (deployApps) {
  name: '${environmentName}-apps'
  scope: appsResourceGroup
  params: {
    location: location
    infrastructureSubnetId: network.outputs.acaSubnetId
    managedEnvironmentName: 'cae-${environmentName}'
    logAnalyticsWorkspaceName: appsLogAnalyticsWorkspaceName
    logAnalyticsWorkspaceResourceGroupName: appsLogAnalyticsWorkspaceResourceGroupName
    acrName: appsAcrName
    acrResourceGroupName: appsAcrResourceGroupName
    keyVaultName: appsKeyVaultName
    keyVaultResourceGroupName: appsKeyVaultResourceGroupName
    registryHostname: registryHostname
    keycloakHostname: keycloakHostname
    registryImage: registryImage
    authServerImage: authServerImage
    mcpgwImage: mcpgwImage
    keycloakImage: keycloakImage
    keycloakDbHost: keycloakDbHost
    keycloakDbName: keycloakDbName
    keycloakDbUsername: keycloakDbUsername
    keycloakClientSecretName: keycloakClientSecretName
    keycloakM2mClientSecretName: keycloakM2mClientSecretName
    tags: tags
  }
}

module keycloakDbPrivateEndpoint './modules/postgresql-private-endpoint.bicep' = if (deployKeycloakDbPrivateEndpoint) {
  name: '${environmentName}-keycloak-db-private-endpoint'
  scope: networkResourceGroup
  params: {
    location: location
    postgresServerName: keycloakDbServerName
    postgresServerResourceGroupName: keycloakDbResourceGroupName
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    vnetId: network.outputs.vnetId
    tags: tags
  }
}

module privateDns './modules/private-dns.bicep' = {
  name: '${environmentName}-private-dns'
  scope: networkResourceGroup
  dependsOn: [
    edge
    etcd
    openBao
    keycloakVm
  ]
  params: {
    vnetId: network.outputs.vnetId
    edgeIpAddress: '10.60.1.4'
    etcdIpAddress: '10.60.2.4'
    openBaoIpAddress: '10.60.3.4'
    appsIpAddress: deployAppVm ? appVmPrivateIpAddress : ''
    keycloakIpAddress: deployKeycloakVm ? keycloakVmPrivateIpAddress : ''
    acaDefaultDomain: apps.?outputs.?acaDefaultDomain ?? ''
    acaStaticIpAddress: apps.?outputs.?acaStaticIpAddress ?? ''
    tags: tags
  }
}

output resourceGroupNames object = {
  network: networkResourceGroup.name
  edge: edgeResourceGroup.name
  etcd: etcdResourceGroup.name
  openBao: openBaoResourceGroup.name
  apps: appsResourceGroup.name
  registry: registryResourceGroup.name
  keycloak: keycloakResourceGroup.name
  ops: opsResourceGroup.name
}

output vnetId string = network.outputs.vnetId
output bastionName string = network.outputs.bastionName
output bastionPublicIpAddress string = network.outputs.bastionPublicIpAddress
output natPublicIpAddress string = network.outputs.natPublicIpAddress
output platformKeyVaultName string = ops.outputs.keyVaultName
output platformKeyVaultKeyId string = ops.outputs.unsealKeyId
output edgeVmId string = deployFoundationVms ? edge.outputs.vmId : existingEdgeVm.id
output etcdVmId string = deployFoundationVms ? etcd.outputs.vmId : existingEtcdVm.id
output openBaoVmId string = deployFoundationVms ? openBao.outputs.vmId : existingOpenBaoVm.id
output appVmId string = appVm.?outputs.?vmId ?? ''
output appVmPrivateIpAddress string = appVm.?outputs.?privateIpAddress ?? ''
output keycloakVmId string = keycloakVm.?outputs.?vmId ?? ''
output keycloakVmPrivateIpAddress string = keycloakVm.?outputs.?privateIpAddress ?? ''
output managedEnvironmentId string = apps.?outputs.?managedEnvironmentId ?? ''
output registryOriginHost string = apps.?outputs.?registryFqdn ?? ''
