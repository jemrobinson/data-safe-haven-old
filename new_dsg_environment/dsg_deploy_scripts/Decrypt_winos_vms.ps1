Param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$dsgid ,
  [Parameter(Position=1, HelpMessage = "RDS,Data,rdssh1,rdssh2,DC")]
  [string]$decryptvm = (Read-Host -prompt "Enter VM to Decrypt (RDS,Data,rdssh1,rdssh2,DC)")
  ) 

Import-Module Az
Import-Module $PSScriptRoot/DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext;
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

$decryptvm = $decryptvm.ToLower()

if($decryptvm -eq "data") {
    $vm = Get-AzVM -ResourceGroupName $config.dsg.dataserver.rg -Name $config.dsg.dataserver.vmName
    Write-Host "===Decrypting $((Get-AZResource -Resourceid $vm.id).name) ==="
    Disable-AzVMDiskEncryption -ResourceGroupName $vm.ResourceGroupName -VMName $((Get-AZResource -Resourceid $vm.id).name)-Force 
    }

if($decryptvm -eq "rds") {
    $vm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName
    Write-Host "===Decrypting $((Get-AZResource -Resourceid $vm.id).name) ==="
    Disable-AzVMDiskEncryption -ResourceGroupName $vm.ResourceGroupName -VMName $((Get-AZResource -Resourceid $vm.id).name)-Force 
    }

if($decryptvm -eq "rdssh1") {
    $vm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionhost1.vmName
    Write-Host "===Decrypting $((Get-AZResource -Resourceid $vm.id).name) ==="
    Disable-AzVMDiskEncryption -ResourceGroupName $vm.ResourceGroupName -VMName $((Get-AZResource -Resourceid $vm.id).name)-Force 
    }

if($decryptvm -eq "rdssh2") {
    $vm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionhost2.vmName
    Write-Host "===Decrypting $((Get-AZResource -Resourceid $vm.id).name) ==="
    Disable-AzVMDiskEncryption -ResourceGroupName $vm.ResourceGroupName -VMName $((Get-AZResource -Resourceid $vm.id).name)-Force 
    }

if($decryptvm -eq "dc") {
    $vm = Get-AzVM -ResourceGroupName $config.dsg.dc.rg -Name $config.dsg.dc.vmName
    Write-Host "===Decrypting $((Get-AZResource -Resourceid $vm.id).name) ==="
    Disable-AzVMDiskEncryption -ResourceGroupName $vm.ResourceGroupName -VMName $((Get-AZResource -Resourceid $vm.id).name)-Force 
    }


# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;