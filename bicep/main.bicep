targetScope = 'resourceGroup'

@description('Required. Specifies the Azure location where the key vault should be created.')
param location string = resourceGroup().location

@description('Required. Admin username of the Virtual Machine.')
param adminUsername string

@description('Required. Password or ssh key for the Virtual Machine.')
@secure()
param adminPasswordOrKey string

@description('Optional. Type of authentication to use on the Virtual Machine.')
@allowed([
  'password'
  'sshPublicKey'
])
param authenticationType string = 'password'

@description('Not before date in seconds since 1970-01-01T00:00:00Z.')
param keyNotBefore int = dateTimeToEpoch(utcNow())

@description('Expiry date in seconds since 1970-01-01T00:00:00Z.')
param keyExpiration int = dateTimeToEpoch(dateTimeAdd(utcNow(), 'P1Y'))

module cvm 'confidential-vm.bicep' = {
  name: 'cvm'
  params:{
    adminUsername: adminUsername
    adminPasswordOrKey: adminPasswordOrKey
    authenticationType: authenticationType
    location: location
    vmName: 'skr-cvm'
    osImageName: 'Ubuntu 20.04 LTS Gen 2'
    vmSize: 'Standard_DC2as_v5'
    securityType: 'DiskWithVMGuestState'
    bootDiagnostics: false
    osDiskType: 'Premium_LRS'
  }
}

module akv 'keyvault.bicep' = {
  name: 'akv'
  params:{
    keyVaultName: 'skr-kv${uniqueString(resourceGroup().id)}'
    location: location

    objectId: cvm.outputs.systemAssignedPrincipalId
    keysPermissions: [
      'release'
    ]

    keyName: 'myskrkey'
    keyType: 'RSA-HSM'
    keySize: 4096
    keyExportable: true // Enables release
    keyEnabled: true
    keyOps: ['encrypt','decrypt'] /// encrypt and decrypt only works with RSA keys, not EC keys
    keyNotBefore:keyNotBefore
    keyExpiration: keyExpiration
    releasePolicyContentType: 'application/json; charset=utf-8'
    releasePolicyData: loadFileAsBase64('assets/cvm-release-policy.json')
  }
}
