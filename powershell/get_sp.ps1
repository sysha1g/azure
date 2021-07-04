$credentials = $env:CREDENTIALS
$objectSecret = @()
$objectSecret = ConvertFrom-Json $credentials
[string]$servicePrincipalId = ($objectSecret).clientId
[string]$servicePrincipalKey = ($objectSecret).clientSecret
[string]$tenantId = ($objectSecret).tenantId
Write-Output "servicePrincipalId"
($servicePrincipalId | Format-Hex | Select-Object -Expand Bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ''
Write-Output "servicePrincipalKey"
($servicePrincipalKey | Format-Hex | Select-Object -Expand Bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ''
Write-Output "tenantId"
($tenantId | Format-Hex | Select-Object -Expand Bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ''
