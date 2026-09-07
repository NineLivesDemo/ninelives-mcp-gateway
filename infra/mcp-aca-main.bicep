targetScope = 'resourceGroup'

@description('Azure region for the private Container Apps deployment.')
param location string = resourceGroup().location

@description('Existing VNet used by the private Container Apps environment.')
param vnetName string = 'vnet-ai-access'

@description('Dedicated subnet for the Container Apps environment. It must not be shared with other workloads.')
param acaSubnetName string = 'snet-mcp-aca'

@description('Dedicated subnet CIDR. Workload-profile environments require a delegated subnet.')
param acaSubnetAddressPrefix string = '10.50.2.0/27'

@description('New internal Container Apps environment name.')
param managedEnvironmentName string = 'cae-mcp-private'

@description('Existing Log Analytics workspace receiving ACA platform logs.')
param logAnalyticsWorkspaceName string = 'log-litellm-4bqvj62ztmxmi'

@description('Existing ACR containing immutable application images.')
param acrName string = 'cr4bqvj62ztmxmi'

@description('Existing Key Vault containing runtime secrets.')
param keyVaultName string = 'kv-ai-access'

@description('Registry hostname used for browser redirects and issuer-facing URLs.')
@minLength(3)
@maxLength(253)
param registryHostname string

@description('Keycloak hostname used for browser redirects and issuer metadata.')
@minLength(3)
@maxLength(253)
param keycloakHostname string

@description('Immutable Registry image reference, mirrored to ACR.')
param registryImage string

@description('Immutable auth-server image reference, mirrored to ACR.')
param authServerImage string

@description('Immutable MCP gateway image reference, mirrored to ACR.')
param mcpgwImage string

@description('Immutable Keycloak image reference, mirrored to ACR.')
param keycloakImage string

@description('Immutable cloudflared image reference, mirrored to ACR.')
param cloudflaredImage string

@description('Key Vault secret name containing the Cloudflare tunnel token.')
param cloudflareTunnelSecretName string = 'cloudflare-tunnel-token'

@description('Key Vault secret name containing the Registry signing secret.')
param registrySecretKeyName string = 'registry-secret-key'

@description('Key Vault secret name shared by Registry and auth-server for NGINX markers.')
param authServerMarkerSecretName string = 'auth-server-nginx-marker-secret'

@description('Key Vault secret name containing the Atlas connection string.')
param mongodbConnectionStringSecretName string = 'mongodb-connection-string'

@description('Key Vault secret name containing the embeddings API key.')
param embeddingsApiKeySecretName string = 'embeddings-api-key'

@description('Key Vault secret name containing the Keycloak administrator password.')
param keycloakAdminPasswordSecretName string = 'keycloak-admin-password'

@description('Key Vault secret name containing the Keycloak database password.')
param keycloakDbPasswordSecretName string = 'keycloak-db-password'

@description('Keycloak PostgreSQL host.')
param keycloakDbHost string

@description('Keycloak PostgreSQL database name.')
param keycloakDbName string = 'keycloak'

@description('Keycloak PostgreSQL username.')
param keycloakDbUsername string = 'keycloak'

@description('Tags applied to the new Container Apps resources.')
param tags object = {
  component: 'mcp-gateway-registry'
  environment: 'pilot'
  managedBy: 'bicep'
  costCenter: 'startup-pilot'
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01' existing = {
  name: acrName
}

module environment './modules/mcp-aca-environment.bicep' = {
  name: 'mcp-aca-environment'
  params: {
    location: location
    vnetName: vnetName
    subnetName: acaSubnetName
    subnetAddressPrefix: acaSubnetAddressPrefix
    environmentName: managedEnvironmentName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    egressPublicIpName: 'pip-mcp-aca-egress'
    natGatewayName: 'nat-mcp-aca-egress'
    tags: tags
  }
}

module registry './modules/mcp-aca-app.bicep' = {
  name: 'mcp-aca-registry'
  params: {
    location: location
    environmentId: environment.outputs.environmentId
    appName: 'mcp-registry'
    containerName: 'registry'
    image: registryImage
    acrLoginServer: acr.properties.loginServer
    acrName: acrName
    keyVaultName: keyVaultName
    targetPort: 8080
    ingressEnabled: true
    ingressExternal: false
    minReplicas: 1
    maxReplicas: 2
    cpu: '1.0'
    memory: '2Gi'
    environmentVariables: [
      { name: 'REGISTRY_URL', value: 'https://${registryHostname}' }
      { name: 'AUTH_SERVER_URL', value: 'http://auth-server:80' }
      { name: 'AUTH_SERVER_EXTERNAL_URL', value: 'https://${registryHostname}' }
      { name: 'KEYCLOAK_URL', value: 'http://keycloak:80' }
      { name: 'KEYCLOAK_EXTERNAL_URL', value: 'https://${keycloakHostname}' }
      { name: 'KEYCLOAK_ADMIN_URL', value: 'https://${keycloakHostname}' }
      { name: 'MCP_HTTPS_REQUIRED', value: 'true' }
      { name: 'SESSION_COOKIE_SECURE', value: 'true' }
      { name: 'MCP_TELEMETRY_DISABLED', value: '1' }
      { name: 'SECRET_KEY', secretRef: 'registry-secret-key' }
      { name: 'AUTH_SERVER_NGINX_MARKER_SECRET', secretRef: 'auth-server-nginx-marker-secret' }
      { name: 'MONGODB_CONNECTION_STRING', secretRef: 'mongodb-connection-string' }
      { name: 'EMBEDDINGS_API_KEY', secretRef: 'embeddings-api-key' }
    ]
    keyVaultSecrets: [
      { name: 'registry-secret-key', keyVaultSecretName: registrySecretKeyName }
      { name: 'auth-server-nginx-marker-secret', keyVaultSecretName: authServerMarkerSecretName }
      { name: 'mongodb-connection-string', keyVaultSecretName: mongodbConnectionStringSecretName }
      { name: 'embeddings-api-key', keyVaultSecretName: embeddingsApiKeySecretName }
    ]
    healthPath: '/health'
    tags: tags
  }
}

module authServer './modules/mcp-aca-app.bicep' = {
  name: 'mcp-aca-auth-server'
  params: {
    location: location
    environmentId: environment.outputs.environmentId
    appName: 'auth-server'
    containerName: 'auth-server'
    image: authServerImage
    acrLoginServer: acr.properties.loginServer
    acrName: acrName
    keyVaultName: keyVaultName
    targetPort: 8888
    ingressEnabled: true
    ingressExternal: false
    minReplicas: 1
    maxReplicas: 2
    cpu: '0.5'
    memory: '1Gi'
    environmentVariables: [
      { name: 'REGISTRY_URL', value: 'http://mcp-registry:80' }
      { name: 'KEYCLOAK_URL', value: 'http://keycloak:80' }
      { name: 'SECRET_KEY', secretRef: 'registry-secret-key' }
      { name: 'AUTH_SERVER_NGINX_MARKER_SECRET', secretRef: 'auth-server-nginx-marker-secret' }
    ]
    keyVaultSecrets: [
      { name: 'registry-secret-key', keyVaultSecretName: registrySecretKeyName }
      { name: 'auth-server-nginx-marker-secret', keyVaultSecretName: authServerMarkerSecretName }
    ]
    healthPath: '/health'
    tags: tags
  }
}

module mcpgw './modules/mcp-aca-app.bicep' = {
  name: 'mcp-aca-mcpgw'
  params: {
    location: location
    environmentId: environment.outputs.environmentId
    appName: 'mcpgw-server'
    containerName: 'mcpgw-server'
    image: mcpgwImage
    acrLoginServer: acr.properties.loginServer
    acrName: acrName
    keyVaultName: keyVaultName
    targetPort: 8003
    ingressEnabled: true
    ingressExternal: false
    minReplicas: 1
    maxReplicas: 2
    cpu: '0.5'
    memory: '1Gi'
    environmentVariables: [
      { name: 'REGISTRY_BASE_URL', value: 'http://mcp-registry:80' }
      { name: 'AUTH_SERVER_URL', value: 'http://auth-server:80' }
    ]
    keyVaultSecrets: []
    healthPath: '/health'
    tags: tags
  }
}

module keycloak './modules/mcp-aca-app.bicep' = {
  name: 'mcp-aca-keycloak'
  params: {
    location: location
    environmentId: environment.outputs.environmentId
    appName: 'keycloak'
    containerName: 'keycloak'
    image: keycloakImage
    acrLoginServer: acr.properties.loginServer
    acrName: acrName
    keyVaultName: keyVaultName
    targetPort: 8080
    ingressEnabled: true
    ingressExternal: false
    minReplicas: 1
    maxReplicas: 1
    cpu: '1.0'
    memory: '2Gi'
    command: ['start']
    environmentVariables: [
      { name: 'KC_DB', value: 'postgres' }
      { name: 'KC_DB_URL', value: 'jdbc:postgresql://${keycloakDbHost}:5432/${keycloakDbName}' }
      { name: 'KC_DB_USERNAME', value: keycloakDbUsername }
      { name: 'KC_DB_PASSWORD', secretRef: 'keycloak-db-password' }
      { name: 'KEYCLOAK_ADMIN', value: 'admin' }
      { name: 'KEYCLOAK_ADMIN_PASSWORD', secretRef: 'keycloak-admin-password' }
      { name: 'KC_HOSTNAME', value: keycloakHostname }
      { name: 'KC_PROXY_HEADERS', value: 'xforwarded' }
      { name: 'KC_HTTP_ENABLED', value: 'true' }
      { name: 'KC_HEALTH_ENABLED', value: 'true' }
    ]
    keyVaultSecrets: [
      { name: 'keycloak-admin-password', keyVaultSecretName: keycloakAdminPasswordSecretName }
      { name: 'keycloak-db-password', keyVaultSecretName: keycloakDbPasswordSecretName }
    ]
    healthPath: '/health/ready'
    tags: tags
  }
}

module cloudflared './modules/mcp-aca-app.bicep' = {
  name: 'mcp-aca-cloudflared'
  params: {
    location: location
    environmentId: environment.outputs.environmentId
    appName: 'cloudflared'
    containerName: 'cloudflared'
    image: cloudflaredImage
    acrLoginServer: acr.properties.loginServer
    acrName: acrName
    keyVaultName: keyVaultName
    targetPort: 0
    ingressEnabled: false
    ingressExternal: false
    minReplicas: 1
    maxReplicas: 2
    cpu: '0.25'
    memory: '0.5Gi'
    environmentVariables: [
      { name: 'TUNNEL_TOKEN', secretRef: 'cloudflare-tunnel-token' }
    ]
    keyVaultSecrets: [
      { name: 'cloudflare-tunnel-token', keyVaultSecretName: cloudflareTunnelSecretName }
    ]
    healthPath: ''
    tags: tags
  }
}

output managedEnvironmentId string = environment.outputs.environmentId
output acaSubnetId string = environment.outputs.subnetId
output egressPublicIp string = environment.outputs.egressPublicIp
output registryAppId string = registry.outputs.appId
output authServerAppId string = authServer.outputs.appId
output mcpgwAppId string = mcpgw.outputs.appId
output keycloakAppId string = keycloak.outputs.appId
output cloudflaredAppId string = cloudflared.outputs.appId
output cloudflaredOriginTargets array = [
  'http://mcp-registry:80'
  'http://keycloak:80'
]
