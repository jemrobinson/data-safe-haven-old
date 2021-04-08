param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

# Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$az_context = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop

# # Setup terraform resource group 
# # ------------------------------------------------------------
# $null = Deploy-ResourceGroup -Name $config.terraform.rg -Location $config.location

# # Setup terraform storage account
# # ------------------------------------------------------------
# $storageAccount = Deploy-StorageAccount -Name $config.terraform.accountName -ResourceGroupName $config.terraform.rg -Location $config.location

# # Create blob storage container
# # ------------------------------------------------------------
# $null = Deploy-StorageContainer -Name $config.terraform.containerName -StorageAccount $storageAccount

# Prepare main.tf file
# ------------------------------------------------------------
$main_file = '../terraform/main.tf'
Copy-Item ../terraform/main.tf_template $main_file
(Get-Content $main_file).replace('<<<subscription_id>>>', $az_context.Subscription.Id) | Set-Content $main_file
(Get-Content $main_file).replace('<<<resource_group_name>>>', $config.terraform.rg) | Set-Content $main_file
(Get-Content $main_file).replace('<<<storage_account_name>>>', $config.terraform.accountName) | Set-Content $main_file
(Get-Content $main_file).replace('<<<container_name>>>', $config.terraform.containerName) | Set-Content $main_file
(Get-Content $main_file).replace('<<<key>>>', $config.terraform.keyName) | Set-Content $main_file

# Prepare terraform.tfvars file
# ------------------------------------------------------------
$tfvars_file = '../terraform/terraform.tfvars'
Copy-Item ../terraform/terraform.tfvars_template $tfvars_file

# DNS
# ------------------------------------------------------------
# (Get-Content $tfvars_file).replace('<<<dns_rg_name>>>', $config.dns.rg) | Set-Content $tfvars_file
# (Get-Content $tfvars_file).replace('<<<dns_rg_location>>>', $config.location) | Set-Content $tfvars_file

# Key Vault
# ------------------------------------------------------------
(Get-Content $tfvars_file).replace('<<<kv_rg_name>>>', $config.keyVault.rg) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_rg_location>>>', $config.location) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_name>>>', $config.keyVault.name) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_location>>>', $config.location) | Set-Content $tfvars_file
$kvSecurityGroupId = (Get-AzADGroup -DisplayName $config.azureAdminGroupName)[0].Id
(Get-Content $tfvars_file).replace('<<<kv_security_group_id>>>', $kvSecurityGroupId) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_secret_name_shm_aad_emergency_admin_username>>>', $config.keyVault.secretNames.aadEmergencyAdminUsername) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_secret_value_shm_aad_emergency_admin_username>>>', "aad.admin.emergency.access") | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_secret_name_shm_aad_emergency_admin_password>>>', $config.keyVault.secretNames.aadEmergencyAdminPassword) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_secret_value_shm_aad_emergency_admin_password>>>', $(New-Password -Length 20)) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_secret_name_shm_domain_admin_username>>>', $config.keyVault.secretNames.domainAdminUsername) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_secret_value_shm_domain_admin_username>>>', "domain$($config.id)admin".ToLower()) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_secret_name_shm_domain_admin_password>>>', $config.keyVault.secretNames.domainAdminPassword) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_secret_value_shm_domain_admin_password>>>', $(New-Password -Length 20)) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_secret_name_shm_vm_safemode_password_dc>>>', $config.dc.safemodePasswordSecretName) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_secret_value_shm_vm_safemode_password_dc>>>', $(New-Password -Length 20)) | Set-Content $tfvars_file


# Networking
# ------------------------------------------------------------
(Get-Content $tfvars_file).replace('<<<net_rg_name>>>', $config.network.vnet.rg) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_rg_location>>>', $config.location) | Set-Content $tfvars_file
$templatePath = Join-Path $PSScriptRoot ".." "arm_templates" "shm-vnet-template.json"
(Get-Content $tfvars_file).replace('<<<net_template_path>>>', $templatePath) | Set-Content $tfvars_file
$templateName = Split-Path -Path "$templatePath" -LeafBase
(Get-Content $tfvars_file).replace('<<<net_name>>>', $templateName) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_ipaddresses_externalntp>>>', $config.time.ntp.serverAddresses -join '", "') | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_nsg_identity_name>>>', $config.network.vnet.subnets.identity.nsg.name) | Set-Content $tfvars_file
$p2sVpnCertificate = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vpnCaCertificatePlain -AsPlaintext
(Get-Content $tfvars_file).replace('<<<net_p2s_vpn_certificate>>>', $p2sVpnCertificate) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_shm_id>>>', ($config.id).ToLower()) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_subnet_firewall_cidr>>>', $config.network.vnet.subnets.firewall.cidr) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_subnet_firewall_name>>>', $config.network.vnet.subnets.firewall.name) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_subnet_gateway_cidr>>>', $config.network.vnet.subnets.gateway.cidr) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_subnet_gateway_name>>>', $config.network.vnet.subnets.gateway.name) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_subnet_identity_cidr>>>', $config.network.vnet.subnets.identity.cidr) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_subnet_identity_name>>>', $config.network.vnet.subnets.identity.name) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_virtual_network_name>>>', $config.network.vnet.name) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_vnet_cidr>>>', $config.network.vnet.cidr) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_vnet_dns_dc1>>>', $config.dc.ip) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_vnet_dns_dc2>>>', $config.dcb.ip) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<net_vpn_cidr>>>', $config.network.vpn.cidr) | Set-Content $tfvars_file

# DC
# ------------------------------------------------------------
(Get-Content $tfvars_file).replace('<<<dc_rg_name>>>', $config.dc.rg) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<dc_rg_location>>>', $config.location) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<dc_rg_name_bootdiagnostics>>>', $config.storage.bootdiagnostics.rg) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<dc_sa_name_bootdiagnostics>>>', $config.storage.bootdiagnostics.accountName) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<dc_rg_name_artifacts>>>', $config.storage.artifacts.rg) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<dc_sa_name_artifacts>>>', $config.storage.artifacts.accountName) | Set-Content $tfvars_file


# Switch back to original subscription
# ------------------------------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop