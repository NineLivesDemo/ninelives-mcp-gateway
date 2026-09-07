targetScope = 'resourceGroup'

@description('Azure region for the Container Apps environment.')
param location string

@description('Existing VNet that will host the private Container Apps environment.')
param vnetName string

@description('Dedicated subnet name for the Container Apps environment.')
param subnetName string

@description('Non-overlapping CIDR reserved exclusively for the Container Apps environment.')
param subnetAddressPrefix string

@description('New private Container Apps environment name.')
param environmentName string

@description('Existing Log Analytics workspace receiving ACA platform logs.')
param logAnalyticsWorkspaceName string

@description('New static public IP used only for deterministic outbound NAT.')
param egressPublicIpName string

@description('New NAT Gateway used only for deterministic outbound NAT.')
param natGatewayName string

@description('Tags applied to new resources.')
param tags object

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vnetName
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource egressPublicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: egressPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2024-07-01' = {
  name: natGatewayName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 10
    publicIpAddresses: [
      {
        id: egressPublicIp.id
      }
    ]
  }
}

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    defaultOutboundAccess: false
    delegations: [
      {
        name: 'container-apps'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
    natGateway: {
      id: natGateway.id
    }
  }
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
      infrastructureSubnetId: acaSubnet.id
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
output subnetId string = acaSubnet.id
output egressPublicIp string = egressPublicIp.properties.ipAddress
