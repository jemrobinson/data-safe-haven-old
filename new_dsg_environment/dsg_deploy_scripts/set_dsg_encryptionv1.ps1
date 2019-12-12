Param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$dsgid
)

Import-Module Az
Import-Module $PSScriptRoot/DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext;
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;


###############################################
# Setting Up NSG for Encryprtion Communication
##############################################

#Set Variables for NSG
$nsgresourceGroupName = $config.dsg.rds.rg
$location = $config.dsg.location
$nsgName = $config.dsg.rds.nsg.sessionhosts.name

$nsg = Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $nsgresourceGroupName 

Write-Host "Creating rule KeyVault_UKSouth in $nsgresourceGroupName for $nsgName" -ForegroundColor Cyan
$nsg = Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $nsgresourceGroupName 
Add-AzNetworkSecurityRuleConfig        -NetworkSecurityGroup $nsg `
                                       -Name KeyVault_UKSouth `
                                       -Description "Required for Key Vault access" `
                                       -Access Allow `
                                       -Protocol Tcp `
                                       -Direction Outbound `
                                       -Priority 3000 `
                                       -SourceAddressPrefix VirtualNetwork `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix AzureKeyVault.UKSouth `
                                       -DestinationPortRange 443
Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
Write-Host "KeyVault_UKSouth rule, Added!" -ForegroundColor Green

Write-Host "Creating rule AzureActiveDirectory in $nsgresourceGroupName for $nsgName" -ForegroundColor Cyan
Add-AzNetworkSecurityRuleConfig        -NetworkSecurityGroup $nsg `
                                       -Name AzureActiveDirectory `
                                       -Description "Required for Key Vault access" `
                                       -Access Allow `
                                       -Protocol Tcp `
                                       -Direction Outbound `
                                       -Priority 3001 `
                                       -SourceAddressPrefix VirtualNetwork `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix AzureActiveDirectory `
                                       -DestinationPortRange 443
Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
Write-Host "AzureActiveDirectory rule, Added!" -ForegroundColor Green

######################################


$servers = ($config.dsg.dc.vmname, $config.dsg.rds.gateway.vmname, $config.dsg.rds.sessionHost1.vmname,$config.dsg.rds.sessionHost2.vmname,$config.dsg.dataserver.vmname)

#KeyVault Variables
$kvname = $config.dsg.KeyVault.name
$kvresourcegroup = $config.dsg.KeyVault.rg
$KeyVault = Get-AzKeyVault -VaultName $kvname -ResourceGroupName $kvresourcegroup
$diskEncryptionKeyVaultUrl = $KeyVault.VaultUri
$KeyVaultResourceId = $KeyVault.ResourceId

#Enable Keyvault for Storing Disk Encryption Keys 
Set-AzKeyVaultAccessPolicy -VaultName $kvname -ResourceGroupName $kvresourcegroup -EnabledForDiskEncryption

foreach ($server in $servers){
  # Skip Provisioned VM
  $vm = get-azvm -Name $server 
  $datadiskNotFound = [bool](((Get-AzVMDiskEncryptionStatus -VMName $vm.name -ResourceGroupName $vm.ResourceGroupName).DataVolumesEncrypted -eq "NoDiskFound"))
  $datadiskEncrypted = [bool](((Get-AzVMDiskEncryptionStatus -VMName $vm.name -ResourceGroupName $vm.ResourceGroupName).DataVolumesEncrypted -eq "Encrypted"))   
  $osDiskEncrpyted = [bool](((Get-AzVMDiskEncryptionStatus -VMName $vm.name -ResourceGroupName $vm.ResourceGroupName).OsVolumeEncrypted -eq "Encrypted"))
  if ( ($osDiskEncrpyted -and $datadiskEncrypted) -or ($osDiskEncrpyted -and $datadiskNotFound)){
    write-host "Skipping $server" -ForegroundColor Yellow
    Continue}
 
  #Stop VM
  Write-Host "Stopping the VM $server" -ForegroundColor Cyan
  $vm | Stop-AzVM -Force

  #Snapshot OS Disk
  Write-Host "Taking snapshot of $server OS disk...." -ForegroundColor Cyan
  $snapshotNameOS = $("Snapshot_"+ $(Get-Date -Format yyyyMMdd) +"_$server"+"_OS")
  $snapshotos = New-AzSnapshotConfig -SourceUri $vm.StorageProfile.OsDisk.ManagedDisk.Id -Location $location -CreateOption copy
  New-AzSnapshot -Snapshot $snapshotos -SnapshotName $snapshotNameOS -ResourceGroupName $vm.ResourceGroupName

  # Snapshoting all datadisks
  $DataDisks = $vm.StorageProfile.DataDisks.Name
  foreach ($DataDisk in $DataDisks)
  {
    $DataDiskID = (Get-AzDisk -Name $DataDisk -ResourceGroupName $vm.ResourceGroupName).Id
    $DataDiskSnapshotConfig = New-AzSnapshotConfig -SourceUri $DataDiskID -Location $Location -CreateOption "Copy"
    $DataSnapshotName = $("Snapshot_"+ $(Get-Date -Format yyyyMMdd) +"_$server"+ $DataDisk )
    New-AzSnapshot -Snapshot $DataDiskSnapshotConfig -SnapshotName $DataSnapshotName -ResourceGroupName $vm.ResourceGroupName
  }
  # Starting VMs
  Write-Host "Starting the VM $server" -ForegroundColor Cyan
  $vm| Start-AzVM

  #Pausing the script to allow VM to start fully.
  Write-Host "Script paused for 100 seconds to allow $server to fully restart....." -ForegroundColor Cyan
  Start-Sleep -Seconds 100
  
  # Starting Encryption
  Write-Host "Starting encryption of $server...." -ForegroundColor Cyan 
  Set-AzVMDiskEncryptionExtension -ResourceGroupName $vm.ResourceGroupName -VMName $server -DiskEncryptionKeyVaultUrl $diskEncryptionKeyVaultUrl -DiskEncryptionKeyVaultId $KeyVaultResourceId -VolumeType All -SkipVmBackup -Force
}

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;