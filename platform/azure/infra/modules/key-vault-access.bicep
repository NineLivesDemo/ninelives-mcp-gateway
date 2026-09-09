@description('Existing platform Key Vault name.')
param keyVaultName string

@description('Managed identity principal ID that may use the OpenBao seal key.')
param principalId string

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource openBaoUnsealKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' existing = {
  parent: keyVault
  name: 'openbao-unseal'
}

resource openBaoCryptoRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openBaoUnsealKey.id, principalId, 'openbao-auto-unseal')
  scope: openBaoUnsealKey
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'e147488a-f6f5-4113-8e2d-b22465e65bf6'
    )
  }
}
