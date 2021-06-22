Param(
    [Parameter(Mandatory=$true)] [String] $HybridGroupName,
    [Parameter(Mandatory=$true)] [String] $username,
    [Parameter(Mandatory=$true)] [String] $password,
    [Parameter(Mandatory=$true)] [String] $tenantId,
    [Parameter(Mandatory=$true)] [String] $subscriptionId,
    [Parameter(Mandatory=$true)] [String] $AAResourceGroupName,
    [Parameter(Mandatory=$true)] [String] $AutomationAccountName,
    [Parameter(Mandatory=$true)] [String] $OMSResourceGroupName,
    [Parameter(Mandatory=$true)] [String] $WorkspaceName,
    [Parameter(Mandatory=$true)] [String] $WorkspaceSubscriptionId
)

Start-Transcript -Path "transcript0.txt" -NoClobber

# Install Az Modules - Needs refinement

$deps1 = @("Az.Accounts","Az.Profile")
$deps2 = @("Az.Blueprint","Az.OperationalInsights")
$additional = @("Az.Automation","Az.Consumption","Az.KeyVault","Az.PolicyInsights","Az.Resources","Az.Security","Az.Subscription","Microsoft.Online.SharePoint.PowerShell","SharePointPnPPowerShellOnline")

# PowerShellGet requires NuGet provider version '2.8.5.201' or newer to interact with NuGet-based repositories
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# Install deps1 which are pre-requisite for subsequest modules
foreach($dep in $deps1){
    Install-Module -Name $dep -AllowClobber -Force
}

#Start-Sleep -s 120

# Install deps2 which are pre-requisite for subsequest modules
foreach($dep in $deps2){
    Install-Module -Name $dep -AllowClobber -Force
}

#Start-Sleep -s 120

# Install additional modules
foreach($mod in $additional){
    Install-Module -Name $mod -AllowClobber -Force
}

# Login to Azure account
$pwd = ConvertTo-SecureString $password -AsPlainText -Force
$pscredential = New-Object -TypeName System.Management.Automation.PSCredential($username, $pwd)
Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant $tenantId

# Get Log Analytics details from Subscription
Set-AzContext -Subscription $WorkspaceSubscriptionId

# Activate the Azure Automation solution in the workspace
$null = Set-AzOperationalInsightsIntelligencePack -ResourceGroupName $OMSResourceGroupName -WorkspaceName $WorkspaceName -IntelligencePackName "AzureAutomation" -Enabled $true

$WorkspaceId = Get-AzOperationalInsightsWorkspace -ResourceGroupName $OMSResourceGroupName -Name $WorkspaceName
$WorkspaceSharedKeys = Get-AzOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $OMSResourceGroupName -Name $WorkspaceName
$WorkspaceKey = $WorkspaceSharedKeys.PrimarySharedKey

# Set the context to the Automation Account Subscription
Set-AzContext -Subscription $subscriptionId

# Get Azure Automation Primary Key and Endpoint
$AutomationAccount = Get-AzAutomationAccount -ResourceGroupName $AAResourceGroupName -Name $AutomationAccountName
$AutomationInfo = Get-AzAutomationRegistrationInfo -ResourceGroupName $AAResourceGroupName -AutomationAccountName $AutomationAccountName
$aaToken = $AutomationInfo.PrimaryKey
$agentServiceEndpoint = $AutomationInfo.Endpoint

# Check for the MMA on the machine
try {

    $mma = New-Object -ComObject 'AgentConfigManager.MgmtSvcCfg'
    
    Write-Output "Configuring the MMA..."
    $mma.AddCloudWorkspace($WorkspaceId, $WorkspaceKey)
    $mma.ReloadConfiguration()

} catch {
    # Download the Microsoft monitoring agent
    Write-Output "Downloading and installing the Microsoft Monitoring Agent..."

    $Source = "https://go.microsoft.com/fwlink/?LinkId=828603"
    $Destination = "$env:temp\MMASetup.exe"

    $null = Invoke-WebRequest -uri $Source -OutFile $Destination
    $null = Unblock-File $Destination

    # Change directory to location of the downloaded MMA
    cd $env:temp

    # Install the MMA
    $cloudType = 0
    $Command = 'C:setup.exe /qn NOAPM=1 ADD_OPINSIGHTS_WORKSPACE=1 OPINSIGHTS_WORKSPACE_AZURE_CLOUD_TYPE=' + $cloudType + ' OPINSIGHTS_WORKSPACE_ID="'+ $WorkspaceID +'" OPINSIGHTS_WORKSPACE_KEY="'+ $WorkspaceKey+'" AcceptEndUserLicenseAgreement=1'
    .\MMASetup.exe $Command
    rm -r "$env:temp"

}

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
