@description('Azure region for the network resources.')
param location string

@description('VNet name.')
param vnetName string

@description('VNet address space.')
param vnetAddressPrefix string

@description('Whether to create the private Registry application VM subnet and NSG.')
param deployApplicationVm bool = false

@description('Whether to preserve existing application and Keycloak subnets even when VM creation is disabled.')
param preserveExistingApplicationSubnets bool = true

@description('Whether to create the private Keycloak VM subnet and NSG.')
param deployKeycloakVm bool = false

@description('Whether to deploy Azure Bastion for private VM access.')
param deployBastion bool = false

@description('Whether to preserve an existing Azure Bastion subnet when Bastion deployment is disabled.')
param preserveExistingBastionSubnet bool = true

@description('Tags applied to network resources.')
param tags object = {}

var edgeSubnetPrefix = '10.60.1.0/24'
var etcdSubnetPrefix = '10.60.2.0/27'
var openBaoSubnetPrefix = '10.60.3.0/27'
var acaSubnetPrefix = '10.60.16.0/23'
var privateEndpointSubnetPrefix = '10.60.20.0/27'
var managementSubnetPrefix = '10.60.21.0/27'
var appsSubnetPrefix = '10.60.4.0/24'
var keycloakSubnetPrefix = '10.60.5.0/24'
var bastionSubnetPrefix = '10.60.22.0/26'

resource natPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-${vnetName}-nat'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
  tags: tags
}

resource natGateway 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'nat-${vnetName}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 10
    publicIpAddresses: [
      {
        id: natPublicIp.id
      }
    ]
  }
  tags: tags
}

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployBastion) {
  name: 'pip-${vnetName}-bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
  tags: tags
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = if (deployBastion) {
  name: 'bas-${vnetName}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'ipconfig-bastion'
        properties: {
          publicIPAddress: {
            id: bastionPublicIp.id
          }
          subnet: {
            id: resourceId(
              'Microsoft.Network/virtualNetworks/subnets',
              vnetName,
              'AzureBastionSubnet'
            )
          }
        }
      }
    ]
  }
  tags: tags
}

resource edgeNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${vnetName}-edge'
  location: location
  properties: {
    securityRules: []
  }
  tags: tags
}

resource etcdNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${vnetName}-etcd'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowEdgeEtcdClientMtls'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: edgeSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '2379'
        }
      }
    ]
  }
  tags: tags
}

resource openBaoNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${vnetName}-openbao'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAcaOpenBaoTls'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: acaSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8200'
        }
      }
      {
        name: 'AllowManagementOpenBaoTls'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: managementSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8200'
        }
      }
      {
        name: 'AllowApplicationOpenBaoTls'
        properties: {
          priority: 120
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: appsSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8200'
        }
      }
    ]
  }
  tags: tags
}

resource appsNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = if (deployApplicationVm || preserveExistingApplicationSubnets) {
  name: 'nsg-${vnetName}-apps'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowEdgeRegistryHttp'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: edgeSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8080'
        }
      }
      {
        name: 'AllowBastionSsh'
        properties: {
          priority: 105
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'AllowManagementSsh'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: managementSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'AllowEdgeSsh'
        properties: {
          priority: 115
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: edgeSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
  tags: tags
}

resource keycloakNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = if (deployKeycloakVm || preserveExistingApplicationSubnets) {
  name: 'nsg-${vnetName}-keycloak'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowEdgeKeycloakHttp'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: edgeSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8080'
        }
      }
      {
        name: 'AllowRegistryKeycloakHttp'
        properties: {
          priority: 105
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: appsSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8080'
        }
      }
      {
        name: 'AllowBastionSsh'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'AllowManagementSsh'
        properties: {
          priority: 115
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: managementSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
  tags: tags
}

var applicationSubnet = {
  name: 'snet-apps'
  properties: {
    addressPrefix: appsSubnetPrefix
    natGateway: {
      id: natGateway.id
    }
    networkSecurityGroup: {
      id: appsNsg.id
    }
  }
}

var keycloakSubnet = {
  name: 'snet-keycloak'
  properties: {
    addressPrefix: keycloakSubnetPrefix
    natGateway: {
      id: natGateway.id
    }
    networkSecurityGroup: {
      id: keycloakNsg.id
    }
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: concat(
      [
      {
        name: 'snet-edge'
        properties: {
          addressPrefix: edgeSubnetPrefix
          natGateway: {
            id: natGateway.id
          }
          networkSecurityGroup: {
            id: edgeNsg.id
          }
        }
      }
      {
        name: 'snet-etcd'
        properties: {
          addressPrefix: etcdSubnetPrefix
          natGateway: {
            id: natGateway.id
          }
          networkSecurityGroup: {
            id: etcdNsg.id
          }
        }
      }
      {
        name: 'snet-openbao'
        properties: {
          addressPrefix: openBaoSubnetPrefix
          natGateway: {
            id: natGateway.id
          }
          networkSecurityGroup: {
            id: openBaoNsg.id
          }
        }
      }
      ],
      (deployApplicationVm || preserveExistingApplicationSubnets) ? [applicationSubnet] : [],
      (deployKeycloakVm || preserveExistingApplicationSubnets) ? [keycloakSubnet] : [],
      (deployBastion || preserveExistingBastionSubnet)
      ? [
          {
            name: 'AzureBastionSubnet'
            properties: {
              addressPrefix: bastionSubnetPrefix
            }
          }
        ]
      : [],
      [
      {
        name: 'snet-aca'
        properties: {
          addressPrefix: acaSubnetPrefix
          natGateway: {
            id: natGateway.id
          }
          delegations: [
            {
              name: 'acaDelegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-management'
        properties: {
          addressPrefix: managementSubnetPrefix
        }
      }
      ]
    )
  }
  tags: tags
}

output vnetId string = vnet.id
output bastionName string = bastion.?name ?? ''
output bastionPublicIpAddress string = bastionPublicIp.?properties.?ipAddress ?? ''
output edgeSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-edge')
output etcdSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-etcd')
output openBaoSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-openbao')
output appsSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-apps')
output keycloakSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-keycloak')
output acaSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-aca')
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-private-endpoints')
output managementSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-management')
output natPublicIpAddress string = natPublicIp.properties.ipAddress
