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

@description('Resource group containing the ACR.')
param acrResourceGroupName string

@description('Existing Key Vault name containing runtime secrets.')
param keyVaultName string

@description('Resource group containing the Key Vault.')
param keyVaultResourceGroupName string

@description('Application environment variables.')
param environmentVariables array = []

@description('Key Vault-backed ACA secrets. Each item has name and keyVaultSecretName properties.')
param keyVaultSecrets array = []

@description('Container target port.')
param targetPort int

@description('Whether the app has an ACA HTTP ingress listener.')
param ingressEnabled bool = true

@description('Whether the app is visible outside the private ACA environment.')
param ingressExternal bool = false

@description('Minimum replica count.')
param minReplicas int = 1

@description('Maximum replica count.')
param maxReplicas int = 1

@description('Container CPU expressed as a JSON number.')
param cpu string = '0.5'

@description('Container memory.')
param memory string = '1Gi'

@description('Health endpoint path. Empty disables generated HTTP probes.')
param healthPath string = '/health'

@description('Container port used by generated HTTP probes.')
param healthPort int = targetPort

@description('Scheme used by generated HTTP probes.')
@allowed([
  'HTTP'
  'HTTPS'
])
param healthScheme string = 'HTTP'

@description('Optional container command.')
param command array = []

@description('Optional container arguments.')
param args array = []

@description('Tags applied to the app and its identity.')
param tags object

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultResourceGroupName)
}

resource runtimeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${appName}-identity'
  location: location
  tags: tags
}

module acrPullRole './acr-pull-role.bicep' = {
  name: '${appName}-acr-pull'
  scope: resourceGroup(acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: runtimeIdentity.properties.principalId
  }
}

module keyVaultSecretRoles './key-vault-secret-role.bicep' = [for secret in keyVaultSecrets: {
  name: '${appName}-${secret.name}-key-vault-secret'
  scope: resourceGroup(keyVaultResourceGroupName)
  params: {
    keyVaultName: keyVaultName
    secretName: secret.keyVaultSecretName
    principalId: runtimeIdentity.properties.principalId
  }
}]

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
                port: healthPort
                scheme: healthScheme
              }
              initialDelaySeconds: 20
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: healthPath
                port: healthPort
                scheme: healthScheme
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
output fqdn string = ingressEnabled ? app.properties.configuration.ingress.fqdn : ''
output identityPrincipalId string = runtimeIdentity.properties.principalId
