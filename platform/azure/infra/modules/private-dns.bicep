@description('VNet resource ID to link to the private DNS zone.')
param vnetId string

@description('Static edge VM private address.')
param edgeIpAddress string

@description('Static etcd VM private address.')
param etcdIpAddress string

@description('Static OpenBao VM private address.')
param openBaoIpAddress string

@description('Static application VM private address.')
param appsIpAddress string = ''

@description('Static Keycloak VM private address.')
param keycloakIpAddress string = ''

@description('Default domain of the internal Container Apps environment.')
param acaDefaultDomain string = ''

@description('Static private address of the internal Container Apps environment.')
param acaStaticIpAddress string = ''

@description('Tags applied to DNS resources.')
param tags object = {}

var zoneName = 'platform.internal'

resource privateZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateZone
  name: 'platform-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource edgeRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateZone
  name: 'edge'
  properties: {
    ttl: 60
    aRecords: [
      {
        ipv4Address: edgeIpAddress
      }
    ]
  }
}

resource etcdRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateZone
  name: 'etcd'
  properties: {
    ttl: 60
    aRecords: [
      {
        ipv4Address: etcdIpAddress
      }
    ]
  }
}

resource openBaoRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateZone
  name: 'openbao'
  properties: {
    ttl: 60
    aRecords: [
      {
        ipv4Address: openBaoIpAddress
      }
    ]
  }
}

resource appsRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = if (!empty(appsIpAddress)) {
  parent: privateZone
  name: 'apps'
  properties: {
    ttl: 60
    aRecords: [
      {
        ipv4Address: appsIpAddress
      }
    ]
  }
}

resource keycloakRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = if (!empty(keycloakIpAddress)) {
  parent: privateZone
  name: 'keycloak'
  properties: {
    ttl: 60
    aRecords: [
      {
        ipv4Address: keycloakIpAddress
      }
    ]
  }
}

resource acaPrivateZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (!empty(acaDefaultDomain) && !empty(acaStaticIpAddress)) {
  name: acaDefaultDomain
  location: 'global'
  tags: tags
}

resource acaVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (!empty(acaDefaultDomain) && !empty(acaStaticIpAddress)) {
  parent: acaPrivateZone
  name: 'platform-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource acaWildcardRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = if (!empty(acaDefaultDomain) && !empty(acaStaticIpAddress)) {
  parent: acaPrivateZone
  name: '*.internal'
  properties: {
    ttl: 60
    aRecords: [
      {
        ipv4Address: acaStaticIpAddress
      }
    ]
  }
}

output zoneName string = privateZone.name
output acaZoneName string = !empty(acaDefaultDomain) && !empty(acaStaticIpAddress) ? acaPrivateZone.name : ''
