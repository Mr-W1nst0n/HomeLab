param(
[Parameter(Mandatory = $false)]
[string]$Script:configFilePath ="Z:\Scripts\Provisioning\Config-LAB.xml"
)

Clear-Host

#region Config
$ScriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition
Push-Location $ScriptPath
#endregion

#region functions
function Initialize-Config
{
    Write-Host -ForegroundColor White "INF :  - Getting config.xml..."
    Push-Location $Script:scriptPath
    [boolean]$Script:IsError = $false
    [xml]$Script:xmlinput = (Get-Content $Script:configFilePath -ErrorAction Inquire)
    $Script:VMsLocationPath = $Script:xmlinput.Configuration.VMsLocationPath
    $Script:VMsNetworkInterface = $Script:xmlinput.Configuration.VMsNetworkInterface
    $Script:VMs = $Script:xmlinput.Configuration.VirtualMachines.Settings
    $Script:ISOs = $Script:xmlinput.Configuration.ISO
    $Script:LogTime = Get-Date -Format "yyyyMMddhhmmss"
    Write-Host -ForegroundColor Cyan "INF :  - XML config loaded !"

    If(!(Test-Path .\log))
    {
        $null = New-Item -ItemType Directory -Force -Path .\log
    }
}

function DisableServerManager
{
    Try
    {
        # Disable ServerManager Startup
        Get-ItemPropertyValue -Path HKCU:\Software\Microsoft\ServerManager -Name DoNotOpenServerManagerAtLogon | Out-Null
        Write-Host -f DarkGray "INF - Found RegistryKey ServerManager" $env:COMPUTERNAME 
    }
    
    Catch
    {
        # Disable ServerManager Startup
        New-ItemProperty -Path HKCU:\Software\Microsoft\ServerManager -Name DoNotOpenServerManagerAtLogon -PropertyType DWORD -Value "0x1" –Force | Out-Null
        Write-Host -f Green "INF - Set RegistryKey ServerManager To 1" $env:COMPUTERNAME
    }
}

function TaskbarSmallIcons
{
    Try
    {
        # TaskbarSmallIcons
        Get-ItemPropertyValue -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarSmallIcons | Out-Null
        Write-Host -f DarkGray "INF - Found RegistryKey TaskbarSmallIcons" $env:COMPUTERNAME 
    }
    
    Catch
    {
        # Enable TaskbarSmallIcons
        New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarSmallIcons -PropertyType DWORD -Value "0x1" –Force | Out-Null
        Write-Host -f Green "INF - Set RegistryKey TaskbarSmallIcons To 1" $env:COMPUTERNAME
    }
}

function TaskbarGlomLevel
{
    Try
    {
        # TaskbarGlomLevel
        Get-ItemPropertyValue -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarGlomLevel | Out-Null
        Write-Host -f DarkGray "INF - Found RegistryKey TaskbarGlomLevel" $env:COMPUTERNAME 
    }
    
    Catch
    {
        # Never Combine TaskbarGlomLevel
        #New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarSmallIcons -PropertyType DWORD -Value "0x1" –Force | Out-Null
        Write-Host -f Green "INF - Set RegistryKey TaskbarGlomLevel To 2" $env:COMPUTERNAME
    }
}

Initialize-Config

$credential = Get-Credential

ForEach($VM in $Script:VMs)
{
    #Invoke-Command -FilePath Z:\Scripts\ServerConfiguration.ps1 -ComputerName $VM.Name -Credential $cred
    Invoke-Command -ComputerName $VM.Name `
                    -Credential $credential `
                    -ScriptBlock ${function:DisableServerManager; function:TaskbarSmallIcons}
}