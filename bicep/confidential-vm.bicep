targetScope = 'resourceGroup'

@description('Required. Name of the Virtual Machine.')
param vmName string

@description('Required. Location of the Virtual Machine.')
param location string

@description('Required. Admin username of the Virtual Machine.')
param adminUsername string

@description('Required. Password or ssh key for the Virtual Machine.')
@secure()
param adminPasswordOrKey string

@description('Optional. Size of the VM.')
@allowed([
  'Standard_DC2as_v5'
  'Standard_DC2ads_v5'
  'Standard_EC2as_v5'
  'Standard_EC2ads_v5'
  // goes up to 96 core variants
])
param vmSize string = 'Standard_DC2as_v5'

@description('Optional. OS Image for the Virtual Machine')
@allowed([
  'Windows Server 2022 Gen 2'
  'Windows Server 2019 Gen 2'
  'Ubuntu 20.04 LTS Gen 2'
])
param osImageName string = 'Ubuntu 20.04 LTS Gen 2'

@description('Optional. OS disk type of the Virtual Machine.')
@allowed([
  'Premium_LRS'
  'Standard_LRS'
  'StandardSSD_LRS'
])
param osDiskType string = 'Premium_LRS'

@description('Optional. Type of authentication to use on the Virtual Machine.')
@allowed([
  'password'
  'sshPublicKey'
])
param authenticationType string = 'password'

@description('Optional. Enable boot diagnostics setting of the Virtual Machine.')
@allowed([
  true
  false
])
param bootDiagnostics bool = false

@description('Optional. Specifies the EncryptionType of the managed disk. It is set to DiskWithVMGuestState for encryption of the managed disk along with VMGuestState blob, and VMGuestStateOnly for encryption of just the VMGuestState blob. NOTE: It can be set for only Confidential VMs.')
@allowed([
  'VMGuestStateOnly' // virtual machine guest state (VMGS) disk
  'DiskWithVMGuestState' // Full disk encryption
])
param securityType string = 'DiskWithVMGuestState'

var imageList = {
  'Windows Server 2022 Gen 2': {
    publisher: 'microsoftwindowsserver'
    offer: 'windowsserver'
    sku: '2022-datacenter-smalldisk-g2'
    version: 'latest'
  }
  'Windows Server 2019 Gen 2': {
    publisher: 'microsoftwindowsserver'
    offer: 'windowsserver'
    sku: '2019-datacenter-smalldisk-g2'
    version: 'latest'
  }
  'Ubuntu 20.04 LTS Gen 2': {
    publisher: 'Canonical'
    offer: '0001-com-ubuntu-confidential-vm-focal' // 👈 Specific confidential VM image offer!
    sku: '20_04-lts-cvm' // 👈 Specific confidential VM image SKU!
    version: 'latest'
  }
}

var virtualNetworkName = '${vmName}-vnet'
var subnetName = '${vmName}-vnet-sn'
var subnetResourceId = resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, subnetName)
var addressPrefix = '10.0.0.0/16'
var subnetPrefix = '10.0.0.0/24'

var isWindows = contains(osImageName, 'Windows')

var extensionName = 'GuestAttestation'
var extensionPublisher = isWindows ? 'Microsoft.Azure.Security.WindowsAttestation' : 'Microsoft.Azure.Security.LinuxAttestation'
var extensionVersion = '1.0'
var maaTenantName = 'GuestAttestation'

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2019-02-01' = {
  name: '${vmName}-ip'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2019-02-01' = {
  name: '${vmName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: (isWindows ? 'RDP' : 'SSH')
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: (isWindows ? '3389' : '22')
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-09-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2019-07-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetResourceId
          }
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource confidentialVm 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: vmName
  location: location
  identity:{
    type: 'SystemAssigned'
  }
  properties: {
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: bootDiagnostics
      }
    }
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
          securityProfile: {
            securityEncryptionType: securityType
          }
        }
      }
      imageReference: imageList[osImageName]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: ((authenticationType == 'password') ? json('null') : {
        disablePasswordAuthentication: 'true'
        ssh: {
          publicKeys: [
            {
              keyData: adminPasswordOrKey
              path: '/home/${adminUsername}/.ssh/authorized_keys'
            }
          ]
        }
      })
      windowsConfiguration: (!isWindows ? json('null') : {
        enableAutomaticUpdates: 'true'
        provisionVmAgent: 'true'
      })
    }
    securityProfile: {
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
      securityType: 'ConfidentialVM'
    }
  }
}

resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2020-06-01' = {
  parent: confidentialVm
  name: extensionName
  location: location
  properties: {
    publisher: extensionPublisher
    type: extensionName
    typeHandlerVersion: extensionVersion
    autoUpgradeMinorVersion: true
    settings: {
      AttestationEndpointCfg: {
        MaaSettings: {
          maaEndpoint: ''
          maaTenantName: maaTenantName
        }
        AscSettings: {
          ascReportingEndpoint: ''
          ascReportingFrequency: ''
        }
        useCustomToken: false
        disableAlerts: false
      }
    }
  }
}

@description('The principal ID of the system assigned identity.')
output systemAssignedPrincipalId string = contains(confidentialVm.identity, 'principalId') ? confidentialVm.identity.principalId : ''
