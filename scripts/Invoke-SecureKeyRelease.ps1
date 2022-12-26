#Requires -Version 7
#Requires -RunAsAdministrator
#Requires -PSEdition Core

<#
.SYNOPSIS
    Perform Secure Key Release operation in Azure Key Vault, provided this script is running inside an Azure Confidential Virtual Machine.
.DESCRIPTION
    Perform Secure Key Release operation in Azure Key Vault, provided this script is running inside an Azure Confidential Virtual Machine.
     The release key operation is applicable to all key types. The target key must be marked exportable. This operation requires the keys/release permission.
.PARAMETER -AttestationTenant
    Provide the attestation instance base URI, for example https://mytenant.attest.azure.net.
.PARAMETER -VaultBaseUrl
    Provide the vault name, for example https://myvault.vault.azure.net.
.PARAMETER -KeyName
    Provide the name of the key to get.
.PARAMETER -KeyName
    Provide the version parameter to retrieve a specific version of a key.
.INPUTS
    None.
.OUTPUTS
    System.Management.Automation.PSObject
.EXAMPLE
    PS C:\> .\Invoke-SecureKeyRelease.ps1 -AttestationTenant "https://sharedweu.weu.attest.azure.net" -VaultBaseUrl "https://skr-kvq6srllol2jntw.vault.azure.net/" -KeyName "myskrkey" -KeyVersion "e473cd4c66224d16870bbe2eb4c58078"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]
    $AttestationTenant,
    [Parameter(Mandatory = $true)]
    [string]
    $VaultBaseUrl,
    [Parameter(Mandatory = $true)]
    [string]
    $KeyName,
    [Parameter(Mandatory = $false)]
    [string]
    $KeyVersion
)
# Check if AttestationClient* exists.
$fileExists = Test-Path -Path "AttestationClient*"
if (!$fileExists) {
    throw "AttestationClient binary not found. Please download it from 'https://github.com/Azure/confidential-computing-cvm-guest-attestation'."
}

# Use correct AttestationClient.
$cmd = $null
if ($isLinux) {
    $cmd = "sudo ./AttestationClient -a $attestationTenant -o token"
}
elseif ($isWindows) {
    $cmd = "./AttestationClientApp.exe -a $attestationTenant -o token"
}

$attestedPlatformReportJwt = Invoke-Expression -Command $cmd
if (!$attestedPlatformReportJwt.StartsWith("eyJ")) {
    throw "AttestationClient failed to get an attested platform report."
}

## Get access token from IMDS for Key Vault
$uri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net'
$kvTokenResponse = Invoke-WebRequest -Uri  $uri -Headers @{Metadata = "true" }
if ($reponse.StatusCode -ne 200) {
    throw "Unable to get access token. Ensure Azure Managed Identity is enabled."
}
$kvAccessToken = ($kvTokenResponse.Content | ConvertFrom-Json).access_token

# Perform release key operation
if (string.IsNullOrEmpty($keyVersion)) {
    $kvReleaseKeyUrl = "{0}/keys/{1}/release?api-version=7.3" -f $vaultBaseUrl, $keyName
}
else {
    $kvReleaseKeyUrl = "{0}/keys/{1}/{2}/release?api-version=7.3" -f $vaultBaseUrl, $keyName, $keyVersion
}

$kvReleaseKeyHeaders = @{
    Authorization  = "Bearer $kvAccessToken"
    'Content-Type' = 'application/json'
}

$kvReleaseKeyBody = @{
    target = $attestedPlatformReportJwt
}

$kvReleaseKeyResponse = Invoke-WebRequest -Method POST -Uri $kvReleaseKeyUrl -Headers $kvReleaseKeyHeaders -Body ($kvReleaseKeyBody | ConvertTo-Json)
if ($kvReleaseKeyResponse.StatusCode -ne 200) {
    Write-Error -Message "Unable to perform release key operation."
    Write-Error -Message $kvReleaseKeyResponse.Content
}
else {
    $kvReleaseKeyResponse.Content | ConvertFrom-Json
}
