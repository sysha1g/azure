Param(
    [Parameter(Mandatory=$true)] [String] $HybridGroupName,
    [Parameter(Mandatory=$true)] [String] $username,
    [Parameter(Mandatory=$true)] [String] $password,
    [Parameter(Mandatory=$true)] [String] $AAResourceGroupName,
    [Parameter(Mandatory=$true)] [String] $AutomationAccountName
)

# Install Az Modules - Needs refinement

$deps1 = @("Az.Accounts","Az.Profile")
$deps2 = @("Az.Blueprint")
$additional = @("Az.Automation","Az.Consumption","Az.KeyVault","Az.PolicyInsights","Az.Resources","Az.Security","Az.Subscription","Microsoft.Online.SharePoint.PowerShell","SharePointPnPPowerShellOnline")

# Install deps1 which are pre-requisite for subsequest modules
foreach ($Module in $deps1) {

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

        $null = Install-Module -Name $ModuleName -RequiredVersion $ModuleVersion -AllowClobber -Force
        Write-Output " Successfully installed version $ModuleVersion of $ModuleName..."

    } else {
        Write-Output " Required version $ModuleVersion of $ModuleName is installed..."
    }
}
# Install deps2 which are pre-requisite for subsequest modules
foreach ($Module in $deps2) {

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

        $null = Install-Module -Name $ModuleName -RequiredVersion $ModuleVersion -AllowClobber -Force
        Write-Output " Successfully installed version $ModuleVersion of $ModuleName..."

    } else {
        Write-Output " Required version $ModuleVersion of $ModuleName is installed..."
    }
}

foreach ($Module in $additional) {

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

        $null = Install-Module -Name $ModuleName -RequiredVersion $ModuleVersion -AllowClobber -Force
        Write-Output " Successfully installed version $ModuleVersion of $ModuleName..."

    } else {
        Write-Output " Required version $ModuleVersion of $ModuleName is installed..."
    }
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

# wait until the MMA Agent downloads AzureAutomation on to the machine
$azureautomationpath = "C:\\Program Files\\Microsoft Monitoring Agent\\Agent\\AzureAutomation"
$version = (ls | Sort-Object LastWriteTime -Descending | Select -First 1).Name
$automationworkerversionpath = Join-Path $azureautomationpath $version -Resolve
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
