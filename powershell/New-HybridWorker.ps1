Param(
    [Parameter(Mandatory=$true)] [String] $HybridGroupName,
    [Parameter(Mandatory=$true)] [String] $username,
    [Parameter(Mandatory=$true)] [String] $password,
    [Parameter(Mandatory=$true)] [String] $tenantId,
    [Parameter(Mandatory=$true)] [String] $subscriptionId,
    [Parameter(Mandatory=$true)] [String] $AAResourceGroupName,
    [Parameter(Mandatory=$true)] [String] $AutomationAccountName,
    [Parameter(Mandatory=$true)] [String] $OMSResourceGroupName,
    [Parameter(Mandatory=$true)] [String] $WorkspaceName
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
Set-AzContext -Subscription $subscriptionId

# Activate the Azure Automation solution in the workspace
Set-AzOperationalInsightsIntelligencePack -ResourceGroupName $OMSResourceGroupName -WorkspaceName $WorkspaceName -IntelligencePackName "AzureAutomation" -Enabled $true

$WorkspaceId = Get-AzOperationalInsightsWorkspace -ResourceGroupName $OMSResourceGroupName -Name $WorkspaceName
$WorkspaceSharedKeys = Get-AzOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $OMSResourceGroupName -Name $WorkspaceName
$WorkspaceKey = $WorkspaceSharedKeys.PrimarySharedKey

# Get Azure Automation Primary Key and Endpoint
$AutomationAccount = Get-AzAutomationAccount -ResourceGroupName $AAResourceGroupName -Name $AutomationAccountName
$AutomationInfo = Get-AzAutomationRegistrationInfo -ResourceGroupName $AAResourceGroupName -AutomationAccountName $AutomationAccountName
$aaToken = $AutomationInfo.PrimaryKey
$agentServiceEndpoint = $AutomationInfo.Endpoint

#Create path for the MMA agent download
$directoryPathForMMADownload="C:\temp"
if(!(Test-Path -path $directoryPathForMMADownload))  
{  
     New-Item -ItemType directory -Path $directoryPathForMMADownload
     Write-Host "Folder path has been created successfully at: " $directoryPathForMMADownload    
}
else 
{ 
    Write-Host "The given folder path $directoryPathForMMADownload already exists"; 
}

Write-Output "Downloading MMA Agent...."
$outputPath = $directoryPathForMMADownload + "\MMA.exe"

# need to update the MMA Agent exe link for gov clouds
Invoke-WebRequest "https://go.microsoft.com/fwlink/?LinkId=828603" -Out $outputPath

Start-Sleep -s 30


$changeDirectoryToMMALocation = "cd  $directoryPathForMMADownload"
Invoke-Expression $changeDirectoryToMMALocation

Write-Output "Extracting MMA Agent...."
$commandToInstallMMAAgent = ".\MMA.exe /c /t:c:\windows\temp\oms"
Invoke-Expression $commandToInstallMMAAgent

Start-Sleep -s 30


$tmpFolderOfMMA = "cd c:\windows\temp\oms"
Invoke-Expression $tmpFolderOfMMA

$cloudType = 0
Write-Output "Connecting LA Workspace to the MMA Agent...."
$commandToConnectoToLAWorkspace = '.\setup.exe /qn NOAPM=1 ADD_OPINSIGHTS_WORKSPACE=1 OPINSIGHTS_WORKSPACE_AZURE_CLOUD_TYPE=' + $cloudType + ' OPINSIGHTS_WORKSPACE_ID="'+ $workspaceId +'" OPINSIGHTS_WORKSPACE_KEY="'+ $workspaceKey+'" AcceptEndUserLicenseAgreement=1'
Invoke-Expression $commandToConnectoToLAWorkspace

Start-Sleep -Seconds 60

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
