param(
    [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE_ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$dcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminPassword
$loggingPgdbPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.loggingPgdbPassword


# Set up the NSG for the logging server
# -------------------------------------
$nsg = Deploy-NetworkSecurityGroup -Name $config.sre.logging.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                             -Name "OutboundDenyInternet" `
                             -Description "Outbound deny internet" `
                             -Priority 4000 `
                             -Direction Outbound -Access Deny -Protocol * `
                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                             -DestinationAddressPrefix Internet -DestinationPortRange *


# Expand Logging cloudinit
# -----------------------
$loggingCloudInitTemplate = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-logging.template.yaml" | Get-Item | Get-Content -Raw
$loggingCloudInit = $loggingCloudInitTemplate.Replace('<logging-user>',$config.sre.logging.pgusername).
                                              Replace('<logging-password>',$loggingPgdbPassword).
                                              Replace('<logging-db>',$config.sre.logging.pgdatabasename).
                                              Replace('<logging-port>',$config.sre.logging.pgport)
# Encode as base64
$loggingCloudInitEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($loggingCloudInit))


# Create logging resource group
# -----------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.logging.rg -Location $config.sre.location




# Deploy Logging VMs from template
# --------------------------------
Add-LogMessage -Level Info "Deploying Logging VM from template..."
$params = @{
    Administrator_Password = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
    Administrator_User = $dcAdminUsername
    BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
    Logging_Cloud_Init = $loggingCloudInitEncoded
    Logging_IP_Address =  $config.sre.logging.ip
    Logging_Server_Name = $config.sre.logging.vmName
    Logging_VM_Size = $config.sre.logging.vmSize
    Virtual_Network_Name = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group = $config.sre.network.vnet.rg
    Virtual_Network_Subnet = $config.sre.network.subnets.data.name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-logging-template.json") -Params $params -ResourceGroupName $config.sre.logging.rg


# Poll VMs to see when they have finished running
# -----------------------------------------------
Add-LogMessage -Level Info "Waiting for cloud-init provisioning to finish (this will take 5+ minutes)..."
$progress = 0
$loggingStatuses = (Get-AzVM -Name $config.sre.logging.vmName -ResourceGroupName $config.sre.logging.rg -Status).Statuses.Code
# $hackmdStatuses = (Get-AzVM -Name $config.sre.webapps.hackmd.vmName -ResourceGroupName $config.sre.webapps.rg -Status).Statuses.Code
while (-Not ($loggingStatuses.Contains("ProvisioningState/succeeded") -and $loggingStatuses.Contains("PowerState/stopped"))) {
    $progress = [math]::min(100, $progress + 1)
    # $gitlabStatuses = (Get-AzVM -Name $config.sre.webapps.gitlab.vmName -ResourceGroupName $config.sre.webapps.rg -Status).Statuses.Code
    $loggingStatuses = (Get-AzVM -Name $config.sre.logging.vmName -ResourceGroupName $config.sre.logging.rg -Status).Statuses.Code
    Write-Progress -Activity "Deployment status:" -Status "Logging [$($loggingStatuses[0]) $($loggingStatuses[1])]" -PercentComplete $progress
    Start-Sleep 10
}


# While logging server is off, ensure it is bound to correct NSG
# --------------------------------------------------------------
Add-LogMessage -Level Info "Ensure logging server is bound to correct NSG..."
foreach ($vmName in ($config.sre.logging.vmName)) {
    Add-VmToNSG -VMName $vmName -NSGName $nsg.Name
}
Start-Sleep -Seconds 30
Add-LogMessage -Level Info "Summary: NICs associated with '$($nsg.Name)' NSG"
@($nsg.NetworkInterfaces) | ForEach-Object { Add-LogMessage -Level Info "=> $($_.Id.Split('/')[-1])" }


# Finally, reboot the webapp servers
# ----------------------------------
foreach ($nameVMNameParamsPair in (("Logging", $config.sre.logging.vmName))) {
    $name, $vmName = $nameVMNameParamsPair
    Add-LogMessage -Level Info "Rebooting the $name VM: '$vmName'"
    $_ = Restart-AzVM -Name $vmName -ResourceGroupName $config.sre.logging.rg
    if ($?) {
        Add-LogMessage -Level Success "Rebooting the $name VM ($vmName) succeeded"
    } else {
        Add-LogMessage -Level Fatal "Rebooting the $name VM ($vmName) failed!"
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
