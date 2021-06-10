Param(
      [Parameter(Mandatory=$True,Position=1)]
      [string]$hostname
      )
$iisSite = "Default Web Site"
Install-WindowsFeature -name Web-Server -IncludeManagementTools
$cert = (Get-ChildItem cert:\LocalMachine\My | where-object { $_.Subject -like "*$hostname*" } | Select-Object -First 1).Thumbprint
$guid = [guid]::NewGuid().ToString("B")
netsh http add sslcert hostnameport="${hostname}:443" certhash=$cert certstorename=MY appid="$guid"
New-WebBinding -name $iisSite -Protocol https -HostHeader $hostname -Port 443 -SslFlags 1
