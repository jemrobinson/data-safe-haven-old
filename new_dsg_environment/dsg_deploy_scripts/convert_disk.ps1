Param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$dsgid,
  [Parameter(Position=1, HelpMessage = "Enter Disk SKU to use (defaults to 'Standard_LRS, StandardSSD_LRS,Premium_LRS')")]
  [string]$storageType = (Read-Host -prompt "Enter VM size to use (defaults to 'Standard_LRS, StandardSSD_LRS,Premium_LRS')")
)

Import-Module Az
Import-Module $PSScriptRoot/DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Find and Update the storage type

foreach($disk in Get-AzDisk) { 
        Write-Host "===Resizing $(($disk).Name) ==="
    $diskUpdateConfig = New-AzDiskUpdateConfig -AccountType $storageType -DiskSizeGB $disk.DiskSizeGB
    Update-AzDisk -DiskUpdate $diskUpdateConfig -ResourceGroupName $disk.ResourceGroupName `
    -DiskName $disk.Name
     }

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;