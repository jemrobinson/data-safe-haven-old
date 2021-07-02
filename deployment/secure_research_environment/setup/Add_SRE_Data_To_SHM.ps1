param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
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


# Create secrets resource group if it does not exist
# --------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.keyVault.rg -Location $config.sre.location


# Ensure the keyvault exists
# --------------------------
$_ = Deploy-KeyVault -Name $config.sre.keyVault.Name -ResourceGroupName $config.sre.keyVault.rg -Location $config.sre.location
Set-KeyVaultPermissions -Name $config.sre.keyVault.Name -GroupName $config.shm.adminSecurityGroupName
Set-AzKeyVaultAccessPolicy -VaultName $config.sre.keyVault.Name -ResourceGroupName $config.sre.keyVault.rg -EnabledForDeployment


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$hackmdPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.hackmdLdapPassword
$gitlabPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.gitlabLdapPassword
$dsvmPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmLdapPassword
$dataMountPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dataMountPassword
$postgresVmPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.users.ldap.postgres.passwordSecretName
$postgresDbServiceAccountPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.users.serviceAccounts.postgres.passwordSecretName
$testResearcherPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.testResearcherPassword
# Encrypt passwords for passing to script
$hackmdPasswordEncrypted = ConvertTo-SecureString $hackmdPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$gitlabPasswordEncrypted = ConvertTo-SecureString $gitlabPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$dsvmPasswordEncrypted = ConvertTo-SecureString $dsvmPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$dataMountPasswordEncrypted = ConvertTo-SecureString $dataMountPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$postgresVmPasswordEncrypted = ConvertTo-SecureString $postgresVmPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$postgresDbServiceAccountPasswordEncrypted = ConvertTo-SecureString $postgresDbServiceAccountPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)
$testResearcherPasswordEncrypted = ConvertTo-SecureString $testResearcherPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)


# Add SRE users and groups to SHM
# -------------------------------
Add-LogMessage -Level Info "[ ] Adding SRE users and groups to SHM..."
$_ = Set-AzContext -Subscription $config.shm.subscriptionName
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Create_New_SRE_User_Service_Accounts_Remote.ps1"
$params = @{
    shmFqdn = [string]$($config.shm.domain.fqdn)
    sreFqdn = [string]$($config.sre.domain.fqdn)
    shmSystemAdministratorSgName = [string]$($config.shm.domain.securityGroups.serverAdmins.name)
    shmSystemAdministratorSgDescription = [string]$($config.shm.domain.securityGroups.serverAdmins.description)
    systemAdministratorSgName = [string]$($config.sre.domain.securityGroups.systemAdministrators.name)
    systemAdministratorSgDescription = [string]$($config.sre.domain.securityGroups.systemAdministrators.description)
    dataAdministratorSgName = [string]$($config.sre.domain.securityGroups.dataAdministrators.name)
    dataAdministratorSgDescription = [string]$($config.sre.domain.securityGroups.dataAdministrators.description)
    researchUserSgName = [string]$($config.sre.domain.securityGroups.researchUsers.name)
    researchUserSgDescription = [string]$($config.sre.domain.securityGroups.researchUsers.description)
    ldapUserSgName = [string]$($config.shm.domain.securityGroups.dsvmLdapUsers.name)
    securityOuPath = [string]$($config.shm.domain.securityOuPath)
    serviceOuPath = [string]$($config.shm.domain.serviceOuPath)
    researchUserOuPath = [string]$($config.shm.domain.userOuPath)
    hackmdSamAccountName = [string]$($config.sre.users.ldap.hackmd.samAccountName)
    hackmdName = [string]$($config.sre.users.ldap.hackmd.name)
    hackmdPasswordEncrypted = $hackmdPasswordEncrypted
    gitlabSamAccountName = [string]$($config.sre.users.ldap.gitlab.samAccountName)
    gitlabName = [string]$($config.sre.users.ldap.gitlab.name)
    gitlabPasswordEncrypted = $gitlabPasswordEncrypted
    dsvmSamAccountName = [string]$($config.sre.users.ldap.dsvm.samAccountName)
    dsvmName = [string]$($config.sre.users.ldap.dsvm.name)
    dsvmPasswordEncrypted = $dsvmPasswordEncrypted
    postgresDbServiceAccountSamAccountName = [string]$($config.sre.users.serviceAccounts.postgres.samAccountName)
    postgresDbServiceAccountName = [string]$($config.sre.users.serviceAccounts.postgres.name)
    postgresDbServiceAccountPasswordEncrypted = $postgresDbServiceAccountPasswordEncrypted
    postgresVmSamAccountName = [string]$($config.sre.users.ldap.postgres.samAccountName)
    postgresVmName = [string]$($config.sre.users.ldap.postgres.name)
    postgresVmPasswordEncrypted = $postgresVmPasswordEncrypted
    dataMountSamAccountName = [string]$($config.sre.users.datamount.samAccountName)
    dataMountName = [string]$($config.sre.users.datamount.name)
    dataMountPasswordEncrypted = $dataMountPasswordEncrypted
    testResearcherSamAccountName = [string]$($config.sre.users.researchers.test.samAccountName)
    testResearcherName = [string]$($config.sre.users.researchers.test.name)
    testResearcherPasswordEncrypted = $testResearcherPasswordEncrypted
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
