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

$WorkspaceId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $OMSResourceGroupName -Name $WorkspaceName).CustomerId
$WorkspaceSharedKeys = Get-AzOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $OMSResourceGroupName -Name $WorkspaceName
$WorkspaceKey = $WorkspaceSharedKeys.PrimarySharedKey

# Get Azure Automation Primary Key and Endpoint
$AutomationAccount = Get-AzAutomationAccount -ResourceGroupName $AAResourceGroupName -Name $AutomationAccountName
$AutomationInfo = Get-AzAutomationRegistrationInfo -ResourceGroupName $AAResourceGroupName -AutomationAccountName $AutomationAccountName
$aaToken = $AutomationInfo.PrimaryKey
$agentServiceEndpoint = $AutomationInfo.Endpoint


try {
   $MyApp = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -eq "Microsoft Monitoring Agent"}
   $MyApp.Uninstall() 
}
catch {
  Write-Output "Agent cant be removed using this automation."
}

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
$commandToConnectoToLAWorkspace = '.\setup.exe /qn NOAPM=1 ADD_OPINSIGHTS_WORKSPACE=1 OPINSIGHTS_WORKSPACE_AZURE_CLOUD_TYPE=' + $cloudType + ' OPINSIGHTS_WORKSPACE_ID="'+ $WorkspaceId +'" OPINSIGHTS_WORKSPACE_KEY="'+ $WorkspaceKey+'" AcceptEndUserLicenseAgreement=1'
Invoke-Expression $commandToConnectoToLAWorkspace

Start-Sleep -Seconds 60

# wait until the MMA Agent downloads AzureAutomation on to the machine
$azureautomationpath = "C:\\Program Files\\Microsoft Monitoring Agent\\Agent\\AzureAutomation"
$automationworkerversionpath = Join-Path $azureautomationpath "7.*" -Resolve
$workerFolder = Join-Path $automationworkerversionpath "HybridRegistration"

$i = 0
$azureAutomationPresent = $false
while($i -le 5)
{
    $i++
    if($null -eq $workerFolder -or !(Test-Path -path $workerFolder))  
    {  
        Write-Host "Folder path is not present waiting..:  $workerFolder"    
        Start-Sleep -s 60

        $automationworkerversionpath = Join-Path $azureautomationpath "7.*" -Resolve
        $workerFolder = Join-Path $automationworkerversionpath "HybridRegistration"
    }
    else 
    { 
        $azureAutomationPresent = $true
        Write-Host "The given folder path $workerFolder already exists"
        break
    }
    Write-Verbose 'Timedout waiting for Automation folder.'
}

if($azureAutomationPresent){

    $itemLocation = "HKLM:\SOFTWARE\Microsoft\HybridRunbookWorker" 
    $existingRegistration = Get-Item -Path $itemLocation 
    if($null -ne $existingRegistration){ 
        Write-Output "Registry was found..." 
        Remove-Item -Path $itemLocation -Recurse
    } 
    else{   
        Write-Output "Not found..." 
    }

    $azureAutomationDirectory = "cd '$workerFolder'"
    Start-Sleep -s 10
    Invoke-Expression $azureAutomationDirectory

    Import-Module .\HybridRegistration.psd1
    Start-Sleep -s 10
    Add-HybridRunbookWorker -GroupName $HybridGroupName -EndPoint $agentServiceEndpoint -Token $aaToken
}
