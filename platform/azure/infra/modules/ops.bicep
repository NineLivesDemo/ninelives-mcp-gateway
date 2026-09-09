@description('Azure region for operations resources.')
param location string

@description('Globally unique platform Key Vault name.')
param keyVaultName string

@description('Automation Account name.')
param automationAccountName string

@description('Hybrid Runbook Worker group name.')
param hybridWorkerGroupName string = 'platform-workers'

@description('Whether to create the Hybrid Runbook Worker group.')
param deployHybridWorkers bool = false

@description('Resource IDs of existing VMs to register as extension-based Hybrid Workers.')
param hybridWorkerVmResourceIds array = []


@description('Globally unique storage account name for operation locks and audit records.')
param operationsStorageAccountName string

@description('Tags applied to operations resources.')

param tags object = {}

@description('Whether to publish the platform read-only runbook.')
param deployPlatformRunbook bool = false

@description('Immutable URI for the published Python runbook content.')
param platformRunbookContentUri string = ''

@description('Immutable content version or digest for the runbook artifact.')
param platformRunbookContentVersion string = ''


resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
  tags: tags
}

resource openBaoUnsealKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: keyVault
  name: 'openbao-unseal'
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'wrapKey'
      'unwrapKey'
    ]
  }
}


resource operationsStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: operationsStorageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
  }
  tags: tags
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: operationsStorage
  name: 'default'
}

resource lockContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'locks'
  properties: {
    publicAccess: 'None'
  }
}

resource auditContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'audit'
  properties: {
    publicAccess: 'None'
  }
}

resource blobOperationsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(operationsStorage.id, automationAccount.name, 'platform-blob-operations')
  scope: operationsStorage
  properties: {
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
  }
}
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
  }
  tags: tags
}

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output keyVaultUri string = 'https://${keyVault.name}${environment().suffixes.keyvaultDns}/'
output unsealKeyId string = openBaoUnsealKey.id
output automationAccountName string = automationAccount.name
output automationPrincipalId string = automationAccount.identity.principalId
output operationsStorageAccountName string = operationsStorage.name
output operationsStorageAccountId string = operationsStorage.id
output automationHybridServiceUrl string = automationAccount.properties.automationHybridServiceUrl

resource hybridWorkerGroup 'Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups@2023-11-01' = if (deployHybridWorkers) {
  parent: automationAccount
  name: hybridWorkerGroupName
  properties: {
  }
}

resource hybridWorkers 'Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups/hybridRunbookWorkers@2023-11-01' = [for vmResourceId in hybridWorkerVmResourceIds: if (deployHybridWorkers) {
  parent: hybridWorkerGroup
  name: guid(vmResourceId)
  properties: {
    vmResourceId: vmResourceId
  }
}]
resource platformRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (deployPlatformRunbook) {
  name: '${automationAccount.name}/platform-read-only'
  properties: {
    description: 'Read-only platform discovery and planning runbook.'
    runbookType: 'Python3'
    logProgress: false
    logVerbose: false
    publishContentLink: {
      uri: platformRunbookContentUri
      version: platformRunbookContentVersion
    }
  }
}
