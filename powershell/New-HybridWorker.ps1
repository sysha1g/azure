Param(
    [Parameter(Mandatory=$true)] [String] $HybridGroupName,
    [Parameter(Mandatory=$true)] [String] $username,
    [Parameter(Mandatory=$true)] [String] $password,
    [Parameter(Mandatory=$true)] [String] $AAResourceGroupName,
    [Parameter(Mandatory=$true)] [String] $AutomationAccountName
)
Start-Transcript -Path "transcript0.txt" -NoClobber
$OMSResourceGroupName = 'weu-centrallogging-pr-rg'
$WorkspaceName = 'log-centrallogs'
# Install Az Modules - Needs refinement

$deps1 = @("Az.Accounts","Az.Profile")
$deps2 = @("Az.Blueprint","Az.OperationalInsights")
$additional = @("Az.Automation","Az.Consumption","Az.KeyVault","Az.PolicyInsights","Az.Resources","Az.Security","Az.Subscription","Microsoft.Online.SharePoint.PowerShell","SharePointPnPPowerShellOnline")

# PowerShellGet requires NuGet provider version '2.8.5.201' or newer to interact with NuGet-based repositories
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

$deps1 = @("Az.Accounts","Az.Profile")
$deps2 = "Az.Blueprint"
$additional = @("Az.Automation","Az.Consumption","Az.KeyVault","Az.PolicyInsights","Az.Resources","Az.Security","Az.Subscription","Microsoft.Online.SharePoint.PowerShell","SharePointPnPPowerShellOnline")


# Install deps1 which are pre-requisite for subsequest modules
foreach($dep in $deps1){
    $module = Find-Module -Name $dep
    Install-Module -Name $module -AllowClobber -Force
}

Start-Sleep -s 120

# Install deps2 which are pre-requisite for subsequest modules
# Install additional modules
foreach($dep in $deps2){
    $module = Find-Module -Name $dep
    Install-Module -Name $module -AllowClobber -Force
}

Start-Sleep -s 120

# Install additional modules
foreach($mod in $additional){
    $module = Find-Module -Name $mod
    Install-Module -Name $module -AllowClobber -Force
}

# Login to Azure account
$pwd = ConvertTo-SecureString $password -AsPlainText -Force
$pscredential = New-Object -TypeName System.Management.Automation.PSCredential($username, $pwd)
Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant $tenantId

$AutomationAccount = Get-AzAutomationAccount -ResourceGroupName $AAResourceGroupName -Name $AutomationAccountName

# Get Azure Automation Primary Key and Endpoint
$AutomationInfo = Get-AzAutomationRegistrationInfo -ResourceGroupName $AAResourceGroupName -AutomationAccountName $AutomationAccountName
$aaToken = $AutomationInfo.PrimaryKey
$agentServiceEndpoint = $AutomationInfo.Endpoint

# Activate the Azure Automation solution in the workspace
$null = Set-AzOperationalInsightsIntelligencePack -ResourceGroupName $OMSResourceGroupName -WorkspaceName $WorkspaceName -IntelligencePackName "AzureAutomation" -Enabled $true -DefaultProfile

# Sleep until the MMA object has been registered
Write-Output "Waiting for agent registration to complete..."

# Timeout = 180 seconds = 3 minutes
$i = 18

do {
    
    # Check for the MMA folders
    try {
        # Change the directory to the location of the hybrid registration module
        cd "$env:ProgramFiles\Microsoft Monitoring Agent\Agent\AzureAutomation"
        $version = (ls | Sort-Object LastWriteTime -Descending | Select -First 1).Name
        cd "$version\HybridRegistration"

        # Import the module
        Import-Module (Resolve-Path('HybridRegistration.psd1'))

        # Mark the flag as true
        $hybrid = $true
    } catch{

        $hybrid = $false

    }
    # Sleep for 10 seconds
    Start-Sleep -s 10
    $i--

} until ($hybrid -or ($i -le 0))

if ($i -le 0) {
    throw "The HybridRegistration module was not found. Please ensure the Microsoft Monitoring Agent was correctly installed."
}
Add-HybridRunbookWorker -GroupName $HybridGroupName -EndPoint $agentServiceEndpoint -Token $aaToken
Stop-Transcript
