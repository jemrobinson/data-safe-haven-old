param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Path to zip file")]
  [string]$zipFilePath,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Name of container to upload to")]
  [string]$containerName
)

# # Ensure that we are connected to Azure
# $prevContext = Get-AzContext
# if(!$prevContext) {
#   Connect-AzAccount
#   $prevContext = Get-AzContext
# }

# # Temporarily switch to DSG subscription
# $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Upload ZIP file with artifacts
Write-Host " - Uploading '$zipFilePath' to container '$containerName'"
$_ = Set-AzStorageBlobContent -File $zipFilePath -Container $containerName; # -Context $storageAccount.Context;