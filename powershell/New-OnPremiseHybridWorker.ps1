[CmdletBinding()]

Param(
  [Parameter(Mandatory=$true)] [String] $AAResourceGroupName,
  [Parameter(Mandatory=$false)] [String] $OMSResourceGroupName,
  [Parameter(Mandatory=$true)] [String] $SubscriptionID,
  [Parameter(Mandatory=$false)] [String] $TenantID,
  [Parameter(Mandatory=$false)] [String] $WorkspaceName = "hybridWorkspace" + (Get-Random -Maximum 99999),
  [Parameter(Mandatory=$true)] [String] $AutomationAccountName,
  [Parameter(Mandatory=$true)] [String] $HybridGroupName,
  [Parameter(Mandatory=$true)] [String] $username,
  [Parameter(Mandatory=$true)] [String] $password,
  [Parameter(Mandatory=$false)] [PSCredential] $Credential
)

# Stop the script if any errors occur
$ErrorActionPreference = "Stop"

# Add and update modules on the Automation account
Write-Output "Importing necessary modules..."

# Create a list of the modules necessary to register a hybrid worker
$AzureRmModule = @{"Name" = "AzureRM"; "Version" = ""}
$Modules = @($AzureRmModule)

# PowerShellGet requires NuGet provider version '2.8.5.201' or newer to interact with NuGet-based repositories
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# Import modules
foreach ($Module in $Modules) {

    $ModuleName = $Module.Name

    # Find the module version
    if ([string]::IsNullOrEmpty($Module.Version)){
        
        # Find the latest module version if a version wasn't provided
        $ModuleVersion = (Find-Module -Name $ModuleName).Version

    } else {

        $ModuleVersion = $Module.Version

    }

    # Check if the required module is already installed
    $CurrentModule = Get-Module -Name $ModuleName -ListAvailable | where "Version" -eq $ModuleVersion

    if (!$CurrentModule) {

        $null = Install-Module -Name $ModuleName -RequiredVersion $ModuleVersion -Force
        Write-Output " Successfully installed version $ModuleVersion of $ModuleName..."

    } else {
        Write-Output " Required version $ModuleVersion of $ModuleName is installed..."
    }
}

# Install Az Modules - Needs refinement

$deps1 = @("Az.Accounts","Az.Profile")
$deps2 = "Az.Blueprint"
$additional = @("Az.Automation","Az.Consumption","Az.KeyVault","Az.PolicyInsights","Az.Resources","Az.Security","Az.Subscription","Microsoft.Online.SharePoint.PowerShell","SharePointPnPPowerShellOnline")

# Install deps1 which are pre-requisite for subsequest modules
foreach($dep in $deps1){
    $module = Find-Module -Name $dep
    Install-Module -Name $module.Name -RequiredVersion $module.Version -AllowClobber -Force
}
# Install deps2 which are pre-requisite for subsequest modules
$module = Find-Module -Name $deps2
Install-Module -Name $module.Name -RequiredVersion $module.Version -AllowClobber -Force

foreach($mod in $additional){
    $module = Find-Module -Name $mod
    Install-Module -Name $module.Name -RequiredVersion $module.Version -AllowClobber -Force
}

###################################################################################

# Connect to the current Azure account
Write-Output "Pulling Azure account credentials..."

# Login to Azure account
$pwd = ConvertTo-SecureString $password -AsPlainText -Force
$pscredential = New-Object -TypeName System.Management.Automation.PSCredential($username, $pwd)
#Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant $tenantId
Connect-AzureRmAccount -Credential $pscredential -Tenant $tenantId -ServicePrincipal


# Get a reference to the current subscription
#$Subscription = Get-AzureRmSubscription -SubscriptionId $SubscriptionID
# Get the tenant id for this subscription
#$TenantID = $Subscription.TenantId

# Set the active subscription
$null = Set-AzureRmContext -SubscriptionID $SubscriptionID

# Check that the resource groups are valid
$null = Get-AzureRmResourceGroup -Name $AAResourceGroupName

# Check that the automation account is valid
$AutomationAccount = Get-AzureRmAutomationAccount -ResourceGroupName $AAResourceGroupName -Name $AutomationAccountName

# Find the automation account region
$AALocation = $AutomationAccount.Location

# Print out Azure Automation Account name and region
Write-Output("Accessing Azure Automation Account named $AutomationAccountName in region $AALocation...")

# Get Azure Automation Primary Key and Endpoint
$AutomationInfo = Get-AzureRMAutomationRegistrationInfo -ResourceGroupName $AAResourceGroupName -AutomationAccountName $AutomationAccountName
$AutomationPrimaryKey = $AutomationInfo.PrimaryKey
$AutomationEndpoint = $AutomationInfo.Endpoint

# Activate the Azure Automation solution in the workspace
#$null = Set-AzureRmOperationalInsightsIntelligencePack -ResourceGroupName $OMSResourceGroupName -WorkspaceName $WorkspaceName -IntelligencePackName "AzureAutomation" -Enabled $true

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

# Register the hybrid runbook worker
Write-Output "Registering the hybrid runbook worker..."
Remove-HybridRunbookWorker -Url $AutomationEndpoint -Key $AutomationPrimaryKey -MachineName $env:computername
Add-HybridRunbookWorker -Name $HybridGroupName -EndPoint $AutomationEndpoint -Token $AutomationPrimaryKey
