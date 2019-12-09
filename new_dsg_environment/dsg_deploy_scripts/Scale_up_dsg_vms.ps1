param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
  [Parameter(Position=1, HelpMessage = "Enter VM size to use (defaults to 'Standard_DS2_v2')")]
  [string]$vmSize = (Read-Host -prompt "Enter VM size to use (defaults to 'Standard_DS2_v2')"),
  [Parameter(Position=1, HelpMessage = "Compute,RDS,Webapp,Data,Rdssh,DC,GPU")]
  [string]$resizeVM = (Read-Host -prompt "Enter VM to resize (Compute,RDS,Webapp,Data,Rdssh,DC,GPU)"),
  [Parameter(Position=1, HelpMessage = "Compute,RDS,Webapp,Data,Rdssh,DC,GPU")]
  [int]$ipLastOctet 
)

Import-Module Az
Import-Module $PSScriptRoot/DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)


# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

$resizeVM = $resizeVM.ToLower()
 
if($resizeVM -eq "webapp") {
    Write-Host "===Resizing web app servers==="
    $vm = Get-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.gitlab.vmName
    $vm.HardwareProfile.VmSize = $vmSize
    Update-AzVM -VM $vm -ResourceGroupName $config.dsg.linux.rg -NoWait
    $vm = Get-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.hackmd.vmName
    $vm.HardwareProfile.VmSize = $vmSize
    Update-AzVM -VM $vm -ResourceGroupName $config.dsg.linux.rg -NoWait
}
if($resizeVM -eq "data") {
    Write-Host "===Resizing dataserver==="
    $vm = Get-AzVM -ResourceGroupName $config.dsg.dataserver.rg -Name $config.dsg.dataserver.vmName
    $vm.HardwareProfile.VmSize = $vmSize
    Update-AzVM -VM $vm -ResourceGroupName $config.dsg.dataserver.rg -NoWait
}
if($resizeVM -eq "rdssh") {
    Write-Host "===Resizing RDS session hosts==="
    $vm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionHost1.vmName
    $vm.HardwareProfile.VmSize = $vmSize
    Update-AzVM -VM $vm -ResourceGroupName $config.dsg.rds.rg -NoWait
    $vm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionHost2.vmName
    $vm.HardwareProfile.VmSize = $vmSize
    Update-AzVM -VM $vm -ResourceGroupName $config.dsg.rds.rg -NoWait
}
if($resizeVM -eq "rds") {
    Write-Host "===Resizing RDS gateway==="
    $vm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName
    $vm.HardwareProfile.VmSize = $vmSize
    Update-AzVM -VM $vm -ResourceGroupName $config.dsg.rds.rg -NoWait
}
if ($resizeVM -eq "dc") {
    Write-Host "===Resizing AD DC==="
    $vm = Get-AzVM -ResourceGroupName $config.dsg.dc.rg -Name $config.dsg.dc.vmName
    $vm.HardwareProfile.VmSize = $vmSize
    Update-AzVM -VM $vm -ResourceGroupName $config.dsg.dc.rg -NoWait
}
if ($resizeVM -eq "compute") {
    Write-Host "===Resizing Compute ==="
    while ($ipLastOctet.GetType() -ne [int] ) {
        $ipLastOctet = (Read-Host -prompt "Enter LastOctect of Compute or GPU VM: ")
    }
    $vm = Get-AzVM -ResourceGroupName RG_DSG_COMPUTE | Where-Object { ($_.Name -Split "-")[1] -eq $ipLastOctet }
    $vm.HardwareProfile.VmSize = $vmSize
    Update-AzVM -VM $vm -ResourceGroupName $config.dsg.dsvm.rg -NoWait
}


# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;




