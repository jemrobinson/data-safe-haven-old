param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "subscriptionName")]
  [string]$subscriptionName,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "DSG Netbios name")]
  [string]$dsgNetbiosName,
  [Parameter(Position=2, Mandatory = $true, HelpMessage = "DSG DN")]
  [string]$dsgDn,
  [Parameter(Position=3, Mandatory = $true, HelpMessage = "DSG Server admin security group name")]
  [string]$dsgServerAdminSgName,
  [Parameter(Position=4, Mandatory = $true, HelpMessage = "DSG DC admin username")]
  [string]$dsgDcAdminUsername,
  [Parameter(Position=5, Mandatory = $true, HelpMessage = "DSG Identity subnet CIDR")]
  [string]$subnetIdentityCidr,
  [Parameter(Position=6, Mandatory = $true, HelpMessage = "DSG RDS subnet CIDR")]
  [string]$subnetRdsCidr,
  [Parameter(Position=7, Mandatory = $true, HelpMessage = "DSG Data subnet CIDR")]
  [string]$subnetDataCidr,
  [Parameter(Position=8, Mandatory = $true, HelpMessage = "SHM FQDN")]
  [string]$shmFqdn,
  [Parameter(Position=9, Mandatory = $true, HelpMessage = "SHM DC IP")]
  [string]$shmDcIp,
  [Parameter(Position=10, Mandatory = $true, HelpMessage = "Name of the artifacts storage account")]
  [string]$storageAccountName,
  [Parameter(Position=11, Mandatory = $true, HelpMessage = "Name of the artifacts storage container")]
  [string]$storageContainerName,
  [Parameter(Position=12, Mandatory = $true, HelpMessage = "SAS token with read/list rights to the artifacts storage blob container")]
  [string]$sasToken,
  [Parameter(Position=13, Mandatory = $true, HelpMessage = "Names of blobs to dowload from artifacts storage blob container")]
  [string]$pipeSeparatedBlobNames
)

# Ensure that we are connected to Azure
$prevContext = Get-AzContext
if(!$prevContext) {
  Connect-AzAccount
  $prevContext = Get-AzContext
}

# Temporarily switch to DSG subscription
$_ = Set-AzContext -SubscriptionId $subscriptionName;

# Configure AD DC
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "Configure_AD_DC_Remote.ps1"

$params = @{
  dsgNetbiosName = "`"$($dsgNetbiosName)`""
  dsgDn = "`"$($cdsgDn)`""
  dsgServerAdminSgName = "`"$($dsgServerAdminSgName)`""
  dsgDcAdminUsername =  "`"$($dsgDcAdminUsername)`""
  subnetIdentityCidr = "`"$($subnetIdentityCidr)`""
  subnetRdsCidr = "`"$($subnetRdsCidr)`""
  subnetDataCidr = "`"$($subnetDataCidr)`""
  shmFqdn = "`"$($shmFqdn)`""
  shmDcIp = "`"$($shmDcIp)`""
  remoteDir = "`"C:\Scripts\$storageContainerName`""
  storageAccountName = "`"$storageAccountName`""
  storageContainerName = "`"$storageContainerName`""
  sasToken = "`"$sasToken`""
  pipeSeparatedBlobNames = "`"$pipeSeparatedBlobNames`""
};

$vmResourceGroup = $config.dsg.dc.rg
$vmName = $config.dsg.dc.vmName;

Write-Host " - Configuring AD DC"
$result = Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup -Name "$vmName" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params

Write-Output $result.Value;

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;
