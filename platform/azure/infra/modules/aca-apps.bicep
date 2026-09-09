targetScope = 'resourceGroup'

@description('Azure region for the private Container Apps deployment.')
param location string

@description('Dedicated ACA infrastructure subnet resource ID.')
param infrastructureSubnetId string

@description('Private Container Apps environment name.')
param managedEnvironmentName string

@description('Existing Log Analytics workspace name.')
param logAnalyticsWorkspaceName string

@description('Resource group containing the Log Analytics workspace.')
param logAnalyticsWorkspaceResourceGroupName string

@description('Existing ACR name.')
param acrName string

@description('Resource group containing the ACR.')
param acrResourceGroupName string

@description('Existing Key Vault name.')
param keyVaultName string

@description('Resource group containing the Key Vault.')
param keyVaultResourceGroupName string

@description('Registry hostname used for browser redirects and issuer-facing URLs.')
@minLength(3)
@maxLength(253)
param registryHostname string

@description('Keycloak hostname used for browser redirects and issuer metadata.')
@minLength(3)
@maxLength(253)
param keycloakHostname string

@description('Immutable Registry image reference.')
param registryImage string

@description('Immutable auth-server image reference.')
param authServerImage string

@description('Immutable MCP gateway image reference.')
param mcpgwImage string

@description('Immutable Keycloak image reference.')
param keycloakImage string

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

@description('Key Vault secret name containing the Keycloak web client secret.')
param keycloakClientSecretName string = 'keycloak-client-secret'

@description('Key Vault secret name containing the Keycloak M2M client secret.')
param keycloakM2mClientSecretName string = 'keycloak-m2m-client-secret'

@description('Key Vault secret name containing the Keycloak database password.')
param keycloakDbPasswordSecretName string = 'keycloak-db-password'

@description('Keycloak PostgreSQL host.')
param keycloakDbHost string

@description('Keycloak PostgreSQL database name.')
param keycloakDbName string = 'keycloak'

@description('Keycloak PostgreSQL username.')
param keycloakDbUsername string = 'keycloak'

@description('Tags applied to Container Apps resources.')
param tags object

resource acr 'Microsoft.ContainerRegistry/registries@2025-04-01' existing = {
  name: acrName
  scope: resourceGroup(acrResourceGroupName)
}

module environment './aca-environment.bicep' = {
  name: 'platform-aca-environment'
  params: {
    location: location
    infrastructureSubnetId: infrastructureSubnetId
    environmentName: managedEnvironmentName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    logAnalyticsWorkspaceResourceGroupName: logAnalyticsWorkspaceResourceGroupName
    tags: tags
  }
}

module registry './aca-app.bicep' = {
  name: 'platform-aca-registry'
  params: {
    location: location
    environmentId: environment.outputs.environmentId
    appName: 'mcp-registry'
    containerName: 'registry'
    image: registryImage
    acrLoginServer: acr.properties.loginServer
    acrName: acrName
    acrResourceGroupName: acrResourceGroupName
    keyVaultName: keyVaultName
    keyVaultResourceGroupName: keyVaultResourceGroupName
    targetPort: 8080
    ingressEnabled: true
    ingressExternal: true
    minReplicas: 1
    maxReplicas: 2
    cpu: '1.0'
    memory: '2Gi'
    environmentVariables: [
      { name: 'REGISTRY_URL', value: 'https://${registryHostname}' }
      { name: 'AUTH_SERVER_URL', value: 'https://auth-server.${environment.outputs.defaultDomain}' }
      { name: 'AUTH_SERVER_EXTERNAL_URL', value: 'https://${registryHostname}' }
      { name: 'STORAGE_BACKEND', value: 'mongodb' }
      { name: 'KEYCLOAK_URL', value: 'https://keycloak.${environment.outputs.defaultDomain}' }
      // nginx's proxy_ssl_trusted_certificate does not use the system trust
      // store implicitly; use the image's public CA bundle for ACA's HTTPS
      // Keycloak ingress unless a deployment supplies a private CA bundle.
      { name: 'KEYCLOAK_CA_BUNDLE', value: '/etc/ssl/certs/ca-certificates.crt' }
      { name: 'KEYCLOAK_EXTERNAL_URL', value: 'https://${keycloakHostname}' }
      { name: 'KEYCLOAK_ADMIN_URL', value: 'https://${keycloakHostname}' }
      { name: 'KEYCLOAK_REALM', value: 'mcp-gateway' }
      { name: 'KEYCLOAK_ENABLED', value: 'true' }
      { name: 'KEYCLOAK_CLIENT_ID', value: 'mcp-gateway-web' }
      { name: 'KEYCLOAK_CLIENT_SECRET', secretRef: 'keycloak-client-secret' }
      { name: 'KEYCLOAK_M2M_CLIENT_ID', value: 'mcp-gateway-m2m' }
      { name: 'KEYCLOAK_M2M_CLIENT_SECRET', secretRef: 'keycloak-m2m-client-secret' }
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
      { name: 'keycloak-client-secret', keyVaultSecretName: keycloakClientSecretName }
      { name: 'keycloak-m2m-client-secret', keyVaultSecretName: keycloakM2mClientSecretName }
    ]
    healthPath: '/health'
    tags: tags
  }
}

module authServer './aca-app.bicep' = {
  name: 'platform-aca-auth-server'
  params: {
    location: location
    environmentId: environment.outputs.environmentId
    appName: 'auth-server'
    containerName: 'auth-server'
    image: authServerImage
    acrLoginServer: acr.properties.loginServer
    acrName: acrName
    acrResourceGroupName: acrResourceGroupName
    keyVaultName: keyVaultName
    keyVaultResourceGroupName: keyVaultResourceGroupName
    targetPort: 8888
    ingressEnabled: true
    ingressExternal: true
    minReplicas: 1
    maxReplicas: 2
    cpu: '0.5'
    memory: '1Gi'
    environmentVariables: [
      { name: 'REGISTRY_URL', value: 'https://mcp-registry.${environment.outputs.defaultDomain}' }
      { name: 'AUTH_SERVER_EXTERNAL_URL', value: 'https://${registryHostname}' }
      { name: 'KEYCLOAK_URL', value: 'https://keycloak.${environment.outputs.defaultDomain}' }
      { name: 'KEYCLOAK_EXTERNAL_URL', value: 'https://${keycloakHostname}' }
      { name: 'KEYCLOAK_REALM', value: 'mcp-gateway' }
      { name: 'KEYCLOAK_ENABLED', value: 'true' }
      { name: 'KEYCLOAK_CLIENT_ID', value: 'mcp-gateway-web' }
      { name: 'KEYCLOAK_CLIENT_SECRET', secretRef: 'keycloak-client-secret' }
      { name: 'SECRET_KEY', secretRef: 'registry-secret-key' }
      { name: 'AUTH_SERVER_NGINX_MARKER_SECRET', secretRef: 'auth-server-nginx-marker-secret' }
    ]
    keyVaultSecrets: [
      { name: 'registry-secret-key', keyVaultSecretName: registrySecretKeyName }
      { name: 'auth-server-nginx-marker-secret', keyVaultSecretName: authServerMarkerSecretName }
      { name: 'keycloak-client-secret', keyVaultSecretName: keycloakClientSecretName }
    ]
    healthPath: '/health'
    tags: tags
  }
}

module mcpgw './aca-app.bicep' = {
  name: 'platform-aca-mcpgw'
  params: {
    location: location
    environmentId: environment.outputs.environmentId
    appName: 'mcpgw-server'
    containerName: 'mcpgw-server'
    image: mcpgwImage
    acrLoginServer: acr.properties.loginServer
    acrName: acrName
    acrResourceGroupName: acrResourceGroupName
    keyVaultName: keyVaultName
    keyVaultResourceGroupName: keyVaultResourceGroupName
    targetPort: 8003
    ingressEnabled: true
    ingressExternal: true
    minReplicas: 1
    maxReplicas: 2
    cpu: '0.5'
    memory: '1Gi'
    environmentVariables: [
      { name: 'REGISTRY_BASE_URL', value: 'https://mcp-registry.${environment.outputs.defaultDomain}' }
      { name: 'AUTH_SERVER_URL', value: 'https://auth-server.${environment.outputs.defaultDomain}' }
      { name: 'PORT', value: '8003' }
      { name: 'HOST', value: '0.0.0.0' }
    ]
    keyVaultSecrets: []
    healthPath: '/health'
    tags: tags
  }
}

module keycloak './aca-app.bicep' = {
  name: 'platform-aca-keycloak'
  params: {
    location: location
    environmentId: environment.outputs.environmentId
    appName: 'keycloak'
    containerName: 'keycloak'
    image: keycloakImage
    acrLoginServer: acr.properties.loginServer
    acrName: acrName
    acrResourceGroupName: acrResourceGroupName
    keyVaultName: keyVaultName
    keyVaultResourceGroupName: keyVaultResourceGroupName
    targetPort: 8080
    ingressEnabled: true
    ingressExternal: true
    minReplicas: 1
    maxReplicas: 1
    cpu: '1.0'
    memory: '2Gi'
    environmentVariables: [
      { name: 'KC_DB', value: 'postgres' }
      { name: 'KC_DB_URL', value: 'jdbc:postgresql://${keycloakDbHost}:5432/${keycloakDbName}?sslmode=require' }
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
    healthPort: 9000
    healthScheme: 'HTTPS'
    tags: tags
  }
}

output managedEnvironmentId string = environment.outputs.environmentId
output registryAppId string = registry.outputs.appId
output registryFqdn string = registry.outputs.fqdn
output acaDefaultDomain string = environment.outputs.defaultDomain
output acaStaticIpAddress string = environment.outputs.staticIpAddress
output authServerAppId string = authServer.outputs.appId
output mcpgwAppId string = mcpgw.outputs.appId
output keycloakAppId string = keycloak.outputs.appId
