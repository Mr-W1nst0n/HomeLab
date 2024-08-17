param(
    [Parameter(Position=0,mandatory=$true)]
    [string] $FullISOFilePath, # C:\Temp\en-us_windows_server_2022_updated_oct_2023_x64_dvd_63dab61a.iso
    [Parameter(Position=1,mandatory=$true)]
    [ValidateSet("UEFI","Bios")]
    [string] $BootType
    )

#Requires -RunAsAdministrator

Clear-Host

#region Config
[boolean]$IsError = $false
$ScriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition
Push-Location $ScriptPath
Write-Host -ForegroundColor Green "INF :  - Variable loaded !"
#endregion

Try
{
    #Create temp directory
    $newImageDir = New-Item -Path '.\NewImage' -ItemType Directory -Force -ErrorAction Stop
    Write-Host -ForegroundColor DarkGray "INF :  - Folder created !"

    #Check if ISO already mounted
    if(!(Get-DiskImage -ImagePath $FullISOFilePath).Attached)
    {
        #Mount ISO
        $ISOMounted = Mount-DiskImage -ImagePath $FullISOFilePath -StorageType ISO -PassThru -ErrorAction Stop
        $ISODriveLetter = ($ISOMounted | Get-Volume).DriveLetter
    }
    else
    {
        $ISODriveLetter = ((Get-DiskImage -ImagePath $FullISOFilePath) | Get-Volume).DriveLetter
    }

    #Copy Files to temp directory
    Copy-Item -Path ($ISODriveLetter +":\*") -Destination $newImageDir -Recurse -Force -ErrorAction Stop
    Write-Host -ForegroundColor DarkGray "INF :  - File copied in Temp Directory !"

    #Prompt the available USB Drive
    Get-Disk | Where-Object BusType -eq "USB" -ErrorAction Stop
    
    #Get the right USB Stick Drive
    $TargetUSB = $(Write-Host -ForegroundColor Cyan "Select the right USB Stick (Number): " -NoNewLine; Read-Host) 
    $USBDrive = Get-Disk | Where-Object Number -eq $TargetUSB -ErrorAction Stop
    
    #Format the USB Stick Drive (THIS WILL REMOVE EVERYTHING)
    $USBDrive | Clear-Disk -RemoveData -Confirm:$true -PassThru -ErrorAction Stop

    if($BootType -eq "UEFI")
    {
        #Split and copy install.wim (because of the filesize)
        dism /Split-Image /ImageFile:$newImageDir\sources\install.wim /SWMFile:$newImageDir\sources\install.swm /FileSize:4096 /CheckIntegrity /quiet

        #Convert Disk to GPT
        $USBDrive | Set-Disk -PartitionStyle GPT -ErrorAction Stop
 
        #Create partition primary and format to FAT32
        $Volume = $USBDrive | New-Partition -Size 8GB -AssignDriveLetter | Format-Volume -FileSystem FAT32 -NewFileSystemLabel WS2022 -ErrorAction Stop
        
        Write-Host -ForegroundColor DarkGray "INF :  - USB Stick prepared for GPT systems !"  
    }

    elseif($BootType -eq "Bios")
    {
        #Convert Disk to MBR
        $USBDrive | Set-Disk -PartitionStyle MBR -ErrorAction Stop
 
        #Create partition primary and format to NTFS
        $Volume = $USBDrive | New-Partition -UseMaximumSize -AssignDriveLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel WS2022 -ErrorAction Stop

        #Set Partiton to Active
        $Volume | Get-Partition | Set-Partition -IsActive $true

        Write-Host -ForegroundColor DarkGray "INF :  - USB Stick prepared for MBR systems !" 
    }
    
    Write-Host -ForegroundColor DarkGray "INF :  - Transfering files to USB Stick..."

    #Copy Files to USB (Ignore install.wim)
    Copy-Item -Path "$newImageDir\*" -Destination ($Volume.DriveLetter + ":\") -Recurse -Exclude install.wim -ErrorAction Stop

    #Dismount ISO
    Dismount-DiskImage -ImagePath $FullISOFilePath -ErrorAction SilentlyContinue | Out-Null

    #Remove temp directory
    Remove-Item "$newImageDir\*" -Recurse -Force
    Remove-Item $newImageDir -Force

    Write-Host -ForegroundColor Green "INF :  - USB Stick Ready !"
}

Catch
{
    Write-Host -ForegroundColor Red "[ERR] $($_.Exception.Message)"
    Write-Host -ForegroundColor Red "[ERR] $($_.InvocationInfo.PositionMessage)"
    $IsError = $true
}

Finally
{
    if($IsError)
    {
        Write-Warning "One or more error(s) occurred during process."
        Exit 3
    }
    else
    {
        Write-Host -ForegroundColor Green "No error detected during process."
        Exit 0
    }
}