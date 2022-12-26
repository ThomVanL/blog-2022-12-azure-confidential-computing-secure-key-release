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
    $AttestationTenant = "https://sharedweu.weu.attest.azure.net",
    [Parameter(Mandatory = $true)]
    [string]
    $VaultBaseUrl = "https://skr-kvq6srllol2jntw.vault.azure.net/",
    [Parameter(Mandatory = $true)]
    [string]
    $KeyName = "myskrkey",
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
    if($reponse.StatusCode -ne 200){
        throw "Unable to get access token. Ensure Azure Managed Identity is enabled."
    }
    $kvAccessToken = ($kvTokenResponse.Content | ConvertFrom-Json).access_token

    # Perform release key operation
    if(string.IsNullOrEmpty($keyVersion)){
        $kvReleaseKeyUrl = "{0}/keys/{1}/release?api-version=7.3" -f $vaultBaseUrl, $keyName
    } else {
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
    if($kvReleaseKeyResponse.StatusCode -ne 200){
        Write-Error -Message "Unable to perform release key operation."
        Write-Error -Message $kvReleaseKeyResponse.Content
    } else {
        $kvReleaseKeyResponse.Content | ConvertFrom-Json
    }


$certBase64 = "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"
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]([System.Convert]::FromBase64String($certBase64))
$cert | Format-List *

    # $attestationResult.Payload.Issuer -eq $attestationTenant
    # $cert.Issuer -eq $attestationResult.Payload.Issuer