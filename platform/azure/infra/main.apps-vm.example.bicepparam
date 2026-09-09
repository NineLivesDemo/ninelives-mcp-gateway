// Non-deployable example. Replace every YOUR_* value after reviewing the
// image digests, Key Vault secret ownership, and existing Keycloak endpoint.
using './main.bicep'

param environmentName = 'platform-pilot'
param location = 'westus3'
param vnetAddressPrefix = '10.60.0.0/16'
param adminUsername = 'platformadmin'
param adminPublicKey = readEnvironmentVariable('AZURE_ADMIN_PUBLIC_KEY')

param edgeVmSize = 'Standard_D2ls_v7'
param etcdVmSize = 'Standard_D2ls_v7'
param openBaoVmSize = 'Standard_D2ls_v7'
param deployFoundationVms = false
param deployBastion = false
param appVmSize = 'Standard_E2ds_v7'
param appVmPrivateIpAddress = '10.60.4.4'
param keycloakVmSize = 'Standard_E2ds_v7'
param keycloakVmPrivateIpAddress = '10.60.5.4'

param deployRuntimeAccess = false
param deployApps = false
param deployAppVm = true
param deployKeycloakVm = true

param appsAcrName = 'YOUR_ACR_NAME'
param appsAcrResourceGroupName = 'YOUR_ACR_RESOURCE_GROUP'
param registryHostname = 'YOUR_REGISTRY_HOSTNAME'
param keycloakHostname = 'YOUR_KEYCLOAK_HOSTNAME'
param keycloakUrl = 'http://keycloak.platform.internal:8080'
param keycloakExternalUrl = 'https://YOUR_KEYCLOAK_HOSTNAME'
param keycloakDbHost = 'YOUR_KEYCLOAK_DB_HOST'
param keycloakDbServerName = 'YOUR_KEYCLOAK_DB_SERVER'
param keycloakDbResourceGroupName = 'YOUR_KEYCLOAK_DB_RESOURCE_GROUP'
param deployKeycloakDbPrivateEndpoint = false

param registryImage = 'YOUR_ACR_LOGIN_SERVER/registry@sha256:YOUR_REGISTRY_DIGEST'
param authServerImage = 'YOUR_ACR_LOGIN_SERVER/auth-server@sha256:YOUR_AUTH_SERVER_DIGEST'
param mcpgwImage = 'YOUR_ACR_LOGIN_SERVER/mcpgw@sha256:YOUR_MCPGW_DIGEST'
param keycloakImage = 'quay.io/keycloak/keycloak@sha256:89aae522be5c945670620f61bdabed612835fb151de8d5aa7091d093e1718a30'
