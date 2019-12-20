param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
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

Write-Host "===Stopping all compute VMs===" -ForegroundColor Cyan
Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg | Stop-AzVM -Force -NoWait
Write-Host "===Stopping web app servers===" -ForegroundColor Cyan
Stop-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.gitlab.vmName -Force -NoWait
Stop-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.hackmd.vmName -Force -NoWait
Write-Host "===Stopping dataserver===" -ForegroundColor Cyan
Stop-AzVM -ResourceGroupName $config.dsg.dataserver.rg -Name $config.dsg.dataserver.vmName -Force -NoWait
Write-Host "===Stopping RDS session hosts===" -ForegroundColor Cyan
Stop-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionHost1.vmName -Force -NoWait
Stop-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionHost2.vmName -Force -NoWait
Write-Host "===Stopping RDS gateway===" -ForegroundColor Cyan
Stop-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName -Force -NoWait
Write-Host "===Stopping AD DC===" -ForegroundColor Cyan
Stop-AzVM -ResourceGroupName $config.dsg.dc.rg -Name $config.dsg.dc.vmName -Force -NoWait

#Pausing the script to allow VM to shutdown.
Write-Host "Script paused for 200 seconds to allow Servers to Shutdown....." -ForegroundColor Cyan
Start-Sleep -Seconds 200

# Find and Update the storage type

foreach($disk in Get-AzDisk) { 
  Write-Host "===Resizing $(($disk).Name) ===" -ForegroundColor Cyan
$diskUpdateConfig = New-AzDiskUpdateConfig -AccountType $storageType -DiskSizeGB $disk.DiskSizeGB
Update-AzDisk -DiskUpdate $diskUpdateConfig -ResourceGroupName $disk.ResourceGroupName `
-DiskName $disk.Name
}


# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
