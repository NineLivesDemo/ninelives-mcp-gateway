// Provide AZURE_ADMIN_PUBLIC_KEY before use. This file is an example deployment configuration.
using './main.bicep'

param environmentName = 'platform-pilot'
param location = 'westus3'
param vnetAddressPrefix = '10.60.0.0/16'
param adminUsername = 'platformadmin'
param adminPublicKey = readEnvironmentVariable('AZURE_ADMIN_PUBLIC_KEY')

param edgeVmSize = 'Standard_D2ls_v7'
param etcdVmSize = 'Standard_D2ls_v7'
param openBaoVmSize = 'Standard_D2ls_v7'

// Enable these only after the prerequisite secrets and images exist.
param deployRuntimeAccess = false
param deployApps = true

// Existing application dependencies discovered in rg-ai-access.
param appsAcrName = 'cr4bqvj62ztmxmi'
param appsAcrResourceGroupName = 'rg-ai-access'
param appsLogAnalyticsWorkspaceName = 'log-litellm-4bqvj62ztmxmi'
param appsLogAnalyticsWorkspaceResourceGroupName = 'rg-ai-access'
param appsKeyVaultName = 'kv-ai-access'
param appsKeyVaultResourceGroupName = 'rg-ai-access'

param registryHostname = 'registry-github.adriangarciacruz.com'
param keycloakHostname = 'keycloak.adriangarciacruz.com'

param registryImage = 'cr4bqvj62ztmxmi.azurecr.io/registry@sha256:d8649aa821308bb6df7daf9dea9e0c8c50fd4cc7066d2e02570aa248861ed5a7'
param authServerImage = 'cr4bqvj62ztmxmi.azurecr.io/auth-server@sha256:bb2334d1835afb37547793799d99478d38c22896a1f29780535f4bfa63a920c7'
param mcpgwImage = 'cr4bqvj62ztmxmi.azurecr.io/mcpgw@sha256:86df691ab2c6ff613422341245f1d8b6434792cd407a454407f36385644c6a26'
param keycloakImage = 'cr4bqvj62ztmxmi.azurecr.io/keycloak@sha256:20a0f32a329642717e0bf85a916e9491f001b84966235cc269abdbd730d487e2'

param keycloakDbHost = 'psql-litellm-4bqvj62ztmxmi.postgres.database.azure.com'
param keycloakDbServerName = 'psql-litellm-4bqvj62ztmxmi'
param keycloakDbResourceGroupName = 'rg-ai-access'
param keycloakDbName = 'keycloak'
param keycloakDbUsername = 'keycloak'
param deployKeycloakDbPrivateEndpoint = true
