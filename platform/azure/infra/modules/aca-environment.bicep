targetScope = 'resourceGroup'

@description('Azure region for the Container Apps environment.')
param location string

@description('Existing delegated ACA infrastructure subnet resource ID.')
param infrastructureSubnetId string

@description('New private Container Apps environment name.')
param environmentName string

@description('Existing Log Analytics workspace name.')
param logAnalyticsWorkspaceName string

@description('Resource group containing the Log Analytics workspace.')
param logAnalyticsWorkspaceResourceGroupName string

@description('Tags applied to the Container Apps environment.')
param tags object

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
  scope: resourceGroup(logAnalyticsWorkspaceResourceGroupName)
}

resource environment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: listKeys(logAnalytics.id, '2023-09-01').primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: infrastructureSubnetId
      internal: true
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output environmentId string = environment.id
output defaultDomain string = environment.properties.defaultDomain
output staticIpAddress string = environment.properties.staticIp
