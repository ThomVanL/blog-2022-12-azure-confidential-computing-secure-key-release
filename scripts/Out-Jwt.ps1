function Out-Jwt {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Token
    )

    if (!$token.StartsWith("eyJ") -OR !$token.Contains(".")) {
        Write-Error "Invalid token structure"
    }

    $token.Split(".") | ForEach-Object {
        $paddedToken = $_.Replace('-', '+').Replace('_', '/')
        switch ($paddedToken.Length % 4) {
            0 { break; }
            2 { $paddedToken += '==' }
            3 { $paddedToken += '=' }
        }


        [System.Text.Encoding]::UTF8.GetString([convert]::FromBase64String($paddedToken)) | Write-Host

        $paddedToken = $null
    }
}