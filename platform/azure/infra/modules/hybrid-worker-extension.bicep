@description('Azure region containing the VM.')
param location string

@description('Existing Linux VM name.')
param vmName string

@description('Automation Hybrid Service URL from the Automation Account.')
param automationAccountUrl string

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
}

resource hybridWorkerExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'HybridWorkerExtension'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Automation.HybridWorker'
    type: 'HybridWorkerForLinux'
    typeHandlerVersion: '1.1'
    autoUpgradeMinorVersion: true
    settings: {
      AutomationAccountURL: automationAccountUrl
    }
  }
}