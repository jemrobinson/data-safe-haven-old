param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Dns -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureDns -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Cryptography -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/RemoteCommands -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Check that we are using the correct provider
# --------------------------------------------
if ($config.sre.remoteDesktop.provider -ne "MicrosoftRDS") {
    Add-LogMessage -Level Fatal "You should not be running this script when using remote desktop provider '$($config.sre.remoteDesktop.provider)'"
}


# Set constants used in this script
# ---------------------------------
$vmNamePairs = @(("RDS Gateway", $config.sre.remoteDesktop.gateway.vmName),
                 ("RDS Session Host (App server)", $config.sre.remoteDesktop.appSessionHost.vmName))


# Retrieve variables from SHM Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.shm.keyVault.name)'..."
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
$domainAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminUsername -AsPlaintext
$domainJoinGatewayPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.rdsGatewayServers.passwordSecretName -DefaultLength 20 -AsPlaintext
$domainJoinSessionHostPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.rdsSessionServers.passwordSecretName -DefaultLength 20 -AsPlaintext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Retrieve variables from SRE Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.sre.keyVault.name)'..."
$ipAddressFirstSRD = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.compute.cidr -Offset 160
$rdsGatewayAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.remoteDesktop.gateway.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
$rdsAppSessionHostAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.remoteDesktop.appSessionHost.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext


# Ensure that boot diagnostics resource group and storage account exist
# ---------------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$null = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location


# Ensure that SRE resource group and storage accounts exist
# ---------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.storage.artifacts.rg -Location $config.sre.location
$sreStorageAccount = Get-StorageAccount -Name $config.sre.storage.artifacts.account.name -ResourceGroupName $config.sre.storage.artifacts.rg -SubscriptionName $config.sre.subscriptionName -ErrorAction Stop

# Get SHM storage account
# -----------------------
$null = Set-AzContext -Subscription $config.shm.subscriptionName -ErrorAction Stop
$shmStorageAccount = Deploy-StorageAccount -Name $config.shm.storage.artifacts.accountName -ResourceGroupName $config.shm.storage.artifacts.rg -Location $config.shm.location
$null = Set-AzContext -Subscription $config.sre.subscriptionName -ErrorAction Stop


# Create RDS resource group if it does not exist
# ----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.remoteDesktop.rg -Location $config.sre.location


# Deploy RDS from template
# ------------------------
Add-LogMessage -Level Info "Deploying RDS from template..."
$params = @{
    administratorUsername                = $sreAdminUsername
    bootDiagnosticsAccountName           = $config.sre.storage.bootdiagnostics.accountName
    domainName                           = $config.shm.domain.fqdn
    gatewayAdministratorPassword         = (ConvertTo-SecureString $rdsGatewayAdminPassword -AsPlainText -Force)
    gatewayDataDiskSizeGb                = [int]$config.sre.remoteDesktop.gateway.disks.data.sizeGb
    gatewayDataDiskType                  = $config.sre.remoteDesktop.gateway.disks.data.type
    gatewayDomainJoinOuPath              = $config.shm.domain.ous.rdsGatewayServers.path
    gatewayDomainJoinPassword            = (ConvertTo-SecureString $domainJoinGatewayPassword -AsPlainText -Force)
    gatewayDomainJoinUser                = $config.shm.users.computerManagers.rdsGatewayServers.samAccountName
    gatewayNsgName                       = $config.sre.remoteDesktop.gateway.nsg.name
    gatewayOsDiskSizeGb                  = [int]$config.sre.remoteDesktop.gateway.disks.os.sizeGb
    gatewayOsDiskType                    = $config.sre.remoteDesktop.gateway.disks.os.type
    gatewayPrivateIpAddress              = $config.sre.remoteDesktop.gateway.ip
    gatewayVmName                        = $config.sre.remoteDesktop.gateway.vmName
    gatewayVmSize                        = $config.sre.remoteDesktop.gateway.vmSize
    sessionHostAppsAdministratorPassword = (ConvertTo-SecureString $rdsAppSessionHostAdminPassword -AsPlainText -Force)
    sessionHostAppsOsDiskSizeGb          = [int]$config.sre.remoteDesktop.appSessionHost.disks.os.sizeGb
    sessionHostAppsOsDiskType            = $config.sre.remoteDesktop.appSessionHost.disks.os.type
    sessionHostAppsPrivateIpAddress      = $config.sre.remoteDesktop.appSessionHost.ip
    sessionHostAppsVmName                = $config.sre.remoteDesktop.appSessionHost.vmName
    sessionHostAppsVmSize                = $config.sre.remoteDesktop.appSessionHost.vmSize
    sessionHostsDomainJoinOuPath         = $config.shm.domain.ous.rdsSessionServers.path
    sessionHostsDomainJoinPassword       = (ConvertTo-SecureString $domainJoinSessionHostPassword -AsPlainText -Force)
    sessionHostsDomainJoinUser           = $config.shm.users.computerManagers.rdsSessionServers.samAccountName
    virtualNetworkGatewaySubnetName      = $config.sre.network.vnet.subnets.remoteDesktop.name
    virtualNetworkName                   = $config.sre.network.vnet.name
    virtualNetworkResourceGroupName      = $config.sre.network.vnet.rg
    virtualNetworkSessionHostsSubnetName = $config.sre.network.vnet.subnets.remoteDesktop.name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-rds-template.json") -TemplateParameters $params -ResourceGroupName $config.sre.remoteDesktop.rg


# Get public IP address of RDS gateway
# ------------------------------------
$rdsGatewayVM = Get-AzVM -ResourceGroupName $config.sre.remoteDesktop.rg -Name $config.sre.remoteDesktop.gateway.vmName
$rdsGatewayPrimaryNicId = ($rdsGateWayVM.NetworkProfile.NetworkInterfaces | Where-Object { $_.Primary })[0].Id
$rdsGatewayPublicIp = (Get-AzPublicIpAddress -ResourceGroupName $config.sre.remoteDesktop.rg | Where-Object { $_.IpConfiguration.Id -like "$rdsGatewayPrimaryNicId*" }).IpAddress


# Add DNS records for RDS Gateway
# -------------------------------
Deploy-DnsRecordCollection -PublicIpAddress $rdsGatewayPublicIp `
                           -RecordNameA "@" `
                           -RecordNameCAA "letsencrypt.org" `
                           -RecordNameCName $serverHostname `
                           -ResourceGroupName $config.shm.dns.rg `
                           -SubscriptionName $config.shm.dns.subscriptionName `
                           -TtlSeconds 30 `
                           -ZoneName $config.sre.domain.fqdn


# Create blob containers in SRE storage account
# ---------------------------------------------
Add-LogMessage -Level Info "Creating blob storage containers in storage account '$($sreStorageAccount.StorageAccountName)'..."
foreach ($containerName in $config.sre.storage.artifacts.containers.Values) {
    $null = Deploy-StorageContainer -Name $containerName -StorageAccount $sreStorageAccount
    $null = Clear-StorageContainer -Name $containerName -StorageAccount $sreStorageAccount
}


# Upload RDS deployment scripts to SRE storage
# --------------------------------------------
Add-LogMessage -Level Info "Upload RDS deployment scripts to storage..."
# Expand mustache template variables
$config["rdsTemplates"] = @{
    domainAdminUsername = $domainAdminUsername
    ipAddressFirstSRD   = $ipAddressFirstSRD
}
# Upload deploy script
try {
    Add-LogMessage -Level Info "[ ] Uploading RDS deployment script to storage account '$($sreStorageAccount.StorageAccountName)'"
    $temporaryPath = (New-TemporaryFile).FullName
    Expand-MustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "Deploy_RDS_Environment.mustache.ps1") -Parameters $config | Out-File $temporaryPath
    $null = Set-AzStorageBlobContent -Container $config.sre.storage.artifacts.containers.sreScriptsRDS -Context $sreStorageAccount.Context -File $temporaryPath -Blob "Deploy_RDS_Environment.ps1" -Force -ErrorAction Stop
    Remove-Item -Path $temporaryPath
} catch {
    Add-LogMessage -Level Fatal "Uploading RDS deployment script failed!" -Exception $_.Exception
}
# Upload deploy script
try {
    Add-LogMessage -Level Info "[ ] Uploading RDS server list to storage account '$($sreStorageAccount.StorageAccountName)'"
    $temporaryPath = (New-TemporaryFile).FullName
    Expand-MustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "ServerList.mustache.xml") -Parameters $config | Out-File $temporaryPath
    $null = Set-AzStorageBlobContent -Container $config.sre.storage.artifacts.containers.sreScriptsRDS -Context $sreStorageAccount.Context -File $temporaryPath -Blob "ServerList.xml" -Force -ErrorAction Stop
    Remove-Item -Path $temporaryPath
} catch {
    Add-LogMessage -Level Fatal "Uploading RDS server list failed!" -Exception $_.Exception
}


# Upload RDS package installers to SRE storage
# --------------------------------------------
Add-LogMessage -Level Info "[ ] Uploading Windows package installers to storage account '$($sreStorageAccount.StorageAccountName)'..."
try {
    # Chrome
    $null = Set-AzureStorageBlobFromUri -FileUri "http://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise64.msi" -BlobFilename "GoogleChrome_x64.msi" -StorageContainer $config.sre.storage.artifacts.containers.sreArtifactsRDS -StorageContext $sreStorageAccount.Context
    # PuTTY
    $baseUri = "https://the.earth.li/~sgtatham/putty/latest/w64/"
    $filename = $(Invoke-WebRequest -Uri $baseUri).Links | Where-Object { $_.href -like "*installer.msi" } | ForEach-Object { $_.href } | Select-Object -First 1
    $version = ($filename -split "-")[2]
    $null = Set-AzureStorageBlobFromUri -FileUri "$($baseUri.Replace('latest', $version))/$filename" -BlobFilename "PuTTY_x64.msi" -StorageContainer $config.sre.storage.artifacts.containers.sreArtifactsRDS -StorageContext $sreStorageAccount.Context
    Add-LogMessage -Level Success "Uploaded Windows package installers"
} catch {
    Add-LogMessage -Level Fatal "Failed to upload Windows package installers!" -Exception $_.Exception
}


# Import files to RDS VMs
# -----------------------
Add-LogMessage -Level Info "Importing files from storage to RDS VMs..."
# Set correct list of packages from blob storage for each session host
$blobfiles = @{}
$vmNamePairs | ForEach-Object { $blobfiles[$_[1]] = @() }
foreach ($blob in Get-AzStorageBlob -Container $config.sre.storage.artifacts.containers.sreArtifactsRDS -Context $sreStorageAccount.Context) {
    $blobfiles[$config.sre.remoteDesktop.appSessionHost.vmName] += @{$config.sre.storage.artifacts.containers.sreArtifactsRDS = $blob.Name }
}
# ... and for the gateway
foreach ($blob in Get-AzStorageBlob -Container $config.sre.storage.artifacts.containers.sreScriptsRDS -Context $sreStorageAccount.Context) {
    $blobfiles[$config.sre.remoteDesktop.gateway.vmName] += @{$config.sre.storage.artifacts.containers.sreScriptsRDS = $blob.Name }
}
# Copy software and/or scripts to RDS VMs
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Import_And_Install_Blobs.ps1"
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    $containerName = $blobfiles[$vmName] | ForEach-Object { $_.Keys } | Select-Object -First 1
    $fileNames = $blobfiles[$vmName] | ForEach-Object { $_.Values }
    $sasToken = New-ReadOnlyStorageAccountSasToken -SubscriptionName $config.sre.subscriptionName -ResourceGroup $config.sre.storage.artifacts.rg -AccountName $sreStorageAccount.StorageAccountName
    Add-LogMessage -Level Info "[ ] Copying $($fileNames.Count) files to $name"
    $params = @{
        blobNameArrayB64     = $fileNames | ConvertTo-Json -Depth 99 | ConvertTo-Base64
        downloadDir          = $config.sre.remoteDesktop.gateway.installationDirectory
        sasTokenB64          = $sasToken | ConvertTo-Base64
        shareOrContainerName = $containerName
        storageAccountName   = $sreStorageAccount.StorageAccountName
        storageService       = "blob"
    }
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.remoteDesktop.rg -Parameter $params
}


# Set locale, install updates and reboot
# --------------------------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    Add-LogMessage -Level Info "Updating ${name}: '$vmName'..."
    $params = @{}
    # The RDS Gateway needs the RDWebClientManagement Powershell module
    if ($name -eq "RDS Gateway") { $params["AdditionalPowershellModules"] = @("RDWebClientManagement") }
    Invoke-WindowsConfiguration -VMName $vmName -ResourceGroupName $config.sre.remoteDesktop.rg -TimeZone $config.sre.time.timezone.windows -NtpServer ($config.shm.time.ntp.serverAddresses)[0] @params
}


# Add VMs to correct NSG
# ----------------------
Add-VmToNSG -VMName $config.sre.remoteDesktop.gateway.vmName -VmResourceGroupName $config.sre.remoteDesktop.rg -NSGName $config.sre.remoteDesktop.gateway.nsg.name -NsgResourceGroupName $config.sre.network.vnet.rg
Add-VmToNSG -VMName $config.sre.remoteDesktop.appSessionHost.vmName -VmResourceGroupName $config.sre.remoteDesktop.rg -NSGName $config.sre.remoteDesktop.appSessionHost.nsg.name -NsgResourceGroupName $config.sre.network.vnet.rg


# Reboot all the RDS VMs
# ----------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $null, $vmName = $nameVMNameParamsPair
    Start-VM -Name $vmName -ResourceGroupName $config.sre.remoteDesktop.rg -ForceRestart
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
