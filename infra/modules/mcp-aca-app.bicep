targetScope = 'resourceGroup'

@description('Azure region for the Container App.')
param location string

@description('Managed Environment resource ID.')
param environmentId string

@description('Container App name.')
param appName string

@description('Container name within the app.')
param containerName string

@description('Immutable container image reference.')
param image string

@description('ACR login server containing the immutable image.')
param acrLoginServer string

@description('Existing ACR name.')
param acrName string

@description('Existing Key Vault name containing runtime secrets.')
param keyVaultName string

@description('Application environment variables. Secret references must match keyVaultSecrets names.')
param environmentVariables array = []

@description('Key Vault-backed ACA secrets. Each item has a name and keyVaultSecretName.')
param keyVaultSecrets array = []

@description('Container target port.')
param targetPort int

@description('Whether the app has an ACA HTTP ingress listener.')
param ingressEnabled bool = true

@description('Whether the ACA ingress is visible outside the environment VNet.')
param ingressExternal bool = false

@description('Minimum replica count. Long-running tunnel connectors must not scale to zero.')
param minReplicas int = 1

@description('Maximum replica count.')
param maxReplicas int = 1

@description('Container CPU expressed as a JSON number, for example 0.5.')
param cpu string = '0.5'

@description('Container memory, for example 1Gi.')
param memory string = '1Gi'

@description('Health endpoint path. Empty disables generated HTTP probes until a canary confirms the path.')
param healthPath string = '/health'

@description('Optional container command.')
param command array = []

@description('Optional container arguments.')
param args array = []

@description('Tags applied to the app and its identity.')
param tags object

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01' existing = {
  name: acrName
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource runtimeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${appName}-identity'
  location: location
  tags: tags
}

var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4633458b-17de-408a-b874-0445c86b69e6'
)

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, runtimeIdentity.id, acrPullRoleDefinitionId)
  scope: acr
  properties: {
    principalId: runtimeIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, runtimeIdentity.id, keyVaultSecretsUserRoleDefinitionId)
  scope: keyVault
  properties: {
    principalId: runtimeIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}

resource app 'Microsoft.App/containerApps@2025-01-01' = {
  name: appName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: ingressEnabled ? {
        external: ingressExternal
        targetPort: targetPort
        transport: 'http'
        allowInsecure: false
      } : null
      registries: [
        {
          server: acrLoginServer
          identity: runtimeIdentity.id
        }
      ]
      secrets: [
        for secret in keyVaultSecrets: {
          name: secret.name
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/${secret.keyVaultSecretName}'
          identity: runtimeIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerName
          image: image
          command: command
          args: args
          env: environmentVariables
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          probes: healthPath == '' ? [] : [
            {
              type: 'Liveness'
              httpGet: {
                path: healthPath
                port: targetPort
              }
              initialDelaySeconds: 20
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: healthPath
                port: targetPort
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              failureThreshold: 6
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output appId string = app.id
output appName string = app.name
output identityPrincipalId string = runtimeIdentity.properties.principalId
