using './main.bicep'

param environmentName = 'platform-pilot'
param location = 'westus3'
param vnetAddressPrefix = '10.60.0.0/16'
param adminUsername = 'platformadmin'
param adminPublicKey = readEnvironmentVariable('AZURE_ADMIN_PUBLIC_KEY')
param edgeVmSize = 'Standard_D2ls_v7'
param etcdVmSize = 'Standard_D2ls_v7'
param openBaoVmSize = 'Standard_D2ls_v7'
param deployRuntimeAccess = false
param deployApps = false
param deployAppVm = false
param deployKeycloakVm = false
