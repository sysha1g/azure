Param(
    [Parameter(Mandatory=$true)] [String] $HybridGroupName,
    [Parameter(Mandatory=$true)] [String] $username,
    [Parameter(Mandatory=$true)] [String] $password,
    [Parameter(Mandatory=$true)] [String] $AAResourceGroupName,
    [Parameter(Mandatory=$true)] [String] $AutomationAccountName
)

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
