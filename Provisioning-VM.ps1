param(
[Parameter(Mandatory = $false)]
[string]$Script:configFilePath ="Z:\CODE\Provisioning\Config-LAB.xml"
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
    $Script:AutoPilotDisks = $Script:xmlinput.Configuration.AutoPilotDisks
    $Script:VMsNetworkInterfaces = $Script:xmlinput.Configuration.VMsNetworkInterfaces
    $Script:VMs = $Script:xmlinput.Configuration.VirtualMachines.Settings
    $Script:ISOs = $Script:xmlinput.Configuration.ISO
    $Script:LogTime = Get-Date -Format "yyyyMMddhhmmss"
    Write-Host -ForegroundColor Cyan "INF :  - XML config loaded !"

    If(!(Test-Path .\log))
    {
        $null = New-Item -ItemType Directory -Force -Path .\log
    }
}

function New-VirtualMachine
{
    Try
    {
        Write-Host -ForegroundColor Gray "INF :  - $($VM.Name) provisioning initiated..."

        If($VM.Name -like "WIN-AP-*")
        {
            If($VM.Version -eq "10")
            {
                # Copy predefined sysprepped vhdx
                New-Item -ItemType Directory -Force -Path "$Script:VMsLocationPath\$($VM.Name)\Virtual Hard Disks" | Out-Null
                Copy-Item -Path "$Script:AutoPilotDisks\SYSPREP-WIN10.vhdx" -Destination "$Script:VMsLocationPath\$($VM.Name)\Virtual Hard Disks\$($VM.Name).vhdx" -Force

                # Provision missing VM dedicated for AUTOPILOT Deployment (use sysprepped vhdx)
                New-VM -Name $VM.Name `
                -MemoryStartupBytes ([convert]::ToInt64($VM.RAM) * 1GB)  `
                -Generation ([convert]::ToInt16($VM.Generation)) `
                -VHDPath "$Script:VMsLocationPath\$($VM.Name)\Virtual Hard Disks\$($VM.Name).vhdx" `
                -Path "$Script:VMsLocationPath" `
                -SwitchName $VMSwitchExternal.Name `
                | Out-Null
            }
        }
        
        Else
        {
            # Provision missing VM
            New-VM -Name $VM.Name `
            -MemoryStartupBytes ([convert]::ToInt64($VM.RAM) * 1GB)  `
            -Generation ([convert]::ToInt16($VM.Generation)) `
            -NewVHDPath "$Script:VMsLocationPath\$($VM.Name)\Virtual Hard Disks\$($VM.Name).vhdx" `
            -NewVHDSizeBytes ([convert]::ToUInt64($VM.OS) * 1GB) `
            -Path "$Script:VMsLocationPath" `
            -SwitchName $VMSwitchInternal.Name `
            | Out-Null
        }
        
        # Assign vCPU
        Set-VMProcessor $($VM.Name) -Count ([convert]::ToInt64($VM.CPU))
        
        # Add SCSI controler
        Add-VMScsiController -VMName $($VM.Name)
        
        if(($VM.Type -eq "Server") -and ($VM.Version -eq "2022"))
        {
            # Define correct ISO
            $ISOPath = $Script:ISOs.Server.'ISO-2022-Path'

            # Set install image
            Add-VMDvdDrive -VMName $($VM.Name) `
                            -ControllerNumber 1 `
                            -ControllerLocation 0 `
                            -Path $ISOPath 
        }

        elseif(($VM.Type -eq "Server") -and ($VM.Version -eq "2019"))
        {
            # Define correct ISO
            $ISOPath = $Script:ISOs.Server.'ISO-2019-Path'

            # Set install image
            Add-VMDvdDrive -VMName $($VM.Name) `
                            -ControllerNumber 1 `
                            -ControllerLocation 0 `
                            -Path $ISOPath 
        }

        elseif(($VM.Type -eq "Client") -and ($VM.Version -eq "10") -and ($VM.Name -notlike "WIN-AP-*"))
        {
            # Define correct ISO
            $ISOPath = $Script:ISOs.Client.'ISO-10-Path'

            # Set install image
            Add-VMDvdDrive -VMName $($VM.Name) `
                            -ControllerNumber 1 `
                            -ControllerLocation 0 `
                            -Path $ISOPath 
        }

        # Set vDVD as first boot device
        Set-VMFirmware -VMName $($VM.Name) -FirstBootDevice (Get-VMDvdDrive -VMName $($VM.Name))
    }

    Catch
    {
        Write-Warning "Generic Error Occured"
    }
}
function Set-HypervisorVMSettings
{
    Write-Host -ForegroundColor Gray "INF :  - $($VM.Name) pushing settings..."

    # Set AutomatiStartAction
    Set-VM -Name $VM.Name -AutomaticStartAction Nothing

    # Set AutomatiStopAction
    Set-VM -Name $VM.Name -AutomaticStopAction ShutDown

    # Enable Guest Integration Services
    Enable-VMIntegrationService -Name "Guest Service Interface" -VMName $VM.Name 
}
#endregion

Initialize-Config

If(!(Test-Path $Script:VMsLocationPath))
{
    # Create Root directory for VMs
    New-Item -ItemType Directory -Force -Path $Script:VMsLocationPath | Out-Null
}

If(!(Test-Path $Script:AutoPilotDisks))
{
    Write-Warning "Sysprep VHDX Path Not Found"
    Exit 3
}

$VMSwitchInternal = Get-VMSwitch -Name $Script:VMsNetworkInterfaces.Internal -ErrorAction Stop
$VMSwitchExternal = Get-VMSwitch -Name $Script:VMsNetworkInterfaces.External -ErrorAction Stop

If(!($VMSwitchInternal) -or (!($VMSwitchExternal)))
{
    Write-Warning "One or more NetworkAdapters not detected in Hypervisor"
    [boolean]$Script:IsError = $true
    Exit 3
}

ForEach($VM in $Script:VMs)
{
    Try
    {
        Get-VM -Name $VM.Name -ErrorAction Stop | Out-Null
    }
    Catch [Microsoft.HyperV.PowerShell.VirtualizationException]
    {
        Write-Warning "$($VM.Name) not found in Hypervisor"
        New-VirtualMachine
        Set-HypervisorVMSettings
    }
    Catch
    {
        Write-Warning "Generic Error Occured"
    }
    Finally
    {
        Write-Host -ForegroundColor Green "INF :  - $($VM.Name) ready in Hypervisor"
    }
}