@description('Azure region for the VM.')
param location string

@description('VM resource name.')
param vmName string

@description('VM size.')
param vmSize string

@description('Linux administrator username.')
param adminUsername string

@description('SSH public key. Password authentication is disabled.')
@secure()
param adminPublicKey string

@description('Subnet resource ID.')
param subnetId string

@description('Static private IPv4 address.')
param privateIpAddress string

@description('Managed data disk size. Set to zero when no separate data disk is needed.')
param dataDiskSizeGb int = 0

@description('Operating system disk size.')
param osDiskSizeGb int = 30

@description('Pinned Ubuntu 24.04 Marketplace image version.')
param ubuntuImageVersion string = '24.04.202608270'

@description('Operating system and data disk type.')
param diskType string = 'StandardSSD_LRS'

@description('Optional non-secret cloud-init content. Secret values are prohibited.')
param customData string = ''

@description('Tags applied to the VM resources.')
param tags object = {}

var dataDiskName = '${vmName}-data'
var nicName = '${vmName}-nic'

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig-primary'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: privateIpAddress
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
  tags: tags
}

resource dataDisk 'Microsoft.Compute/disks@2023-10-02' = if (dataDiskSizeGb > 0) {
  name: dataDiskName
  location: location
  sku: {
    name: diskType
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: dataDiskSizeGb
  }
  tags: tags
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: ubuntuImageVersion
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGb
        managedDisk: {
          storageAccountType: diskType
        }
      }
      dataDisks: dataDiskSizeGb > 0
        ? [
            {
              lun: 0
              createOption: 'Attach'
              caching: 'ReadWrite'
              managedDisk: {
                id: dataDisk.id
              }
            }
          ]
        : []
    }
    osProfile: {
      computerName: take(vmName, 15)
      adminUsername: adminUsername
      customData: empty(customData) ? null : base64(customData)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
        }
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
  tags: tags
}

output vmId string = vm.id
output principalId string = vm.identity.principalId
output privateIpAddress string = privateIpAddress
output dataDiskId string = dataDiskSizeGb > 0 ? dataDisk.id : ''
