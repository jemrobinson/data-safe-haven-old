param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName

$npsSecret = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.npsSecret -DefaultLength 12


# Configure CAP and RAP settings
# ------------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Configure_CAP_And_RAP_Remote.ps1"
Add-LogMessage -Level Info "[ ] Configuring CAP and RAP settings on RDS Gateway"
$params = @{
    sreResearchUserSecurityGroup = [string]$($config.sre.domain.securityGroups.researchUsers.name)
    shmNetbiosName = [string]$($config.shm.domain.netbiosName)
    shmNpsIp = [string]$($config.shm.nps.ip)
    remoteNpsPriority = 1
    remoteNpsTimeout = 60
    remoteNpsBlackout = 60
    remoteNpsSecret = [string]$npsSecret
    remoteNpsRequireAuthAttrib = "Yes"
    remoteNpsAcctSharedSecret = [string]$npsSecret
    remoteNpsServerGroup = [string]"TS GATEWAY SERVER GROUP" # "TS GATEWAY SERVER GROUP" is the group name created when manually configuring an RDS Gateway to use a remote NPS server
}
$scriptPathTemp = "$scriptPath.cap.ps1" 
$params.Keys | % { Add-Content -Path $scriptPathTemp -Value "`$$($_) = `"$($params[$_])`""}
Get-Content -Path $scriptPath | Add-Content -Path $scriptPathTemp 

$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPathTemp -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg 
Remove-Item -Path $scriptPathTemp
Write-Output $result.Value


# Configure SHM NPS for SRE RDS RADIUS client
# -------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
Add-LogMessage -Level Info "Adding RDS Gateway as RADIUS client on SHM NPS"
# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Add_RDS_Gateway_RADIUS_Client_Remote.ps1"
$params = @{
    rdsGatewayIp = [string]$($config.sre.rds.gateway.ip)
    rdsGatewayFqdn = [string]$($config.sre.rds.gateway.fqdn)
    npsSecret = [string]$npsSecret
    sreId = [string]$($config.sre.id)
}
$scriptPathTemp = "$scriptPath.rad.ps1" 
$params.Keys | % { Add-Content -Path $scriptPathTemp -Value "`$$($_) = `"$($params[$_])`""}
Get-Content -Path $scriptPath | Add-Content -Path $scriptPathTemp 

$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPathTemp -VMName $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg
Remove-Item -Path $scriptPathTemp
Write-Output $result.Value
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Restart SHM NPS server
# ----------------------
# We restart the SHM NPS server because we get login failures with an "Event 13" error -
# "A RADIUS message was received from the invalid RADIUS client IP address 10.150.9.250"
# The two reliable ways we have found to fix this are:
# 1. Log into the SHM NPS and reset the RADIUS shared secret via the GUI
# 2. Restart the NPS server
# We can only do (2) in a script, so that is what we do. An NPS restart is quite quick.

# SWitch to SHM subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
Add-LogMessage -Level Info "Restarting NPS Server..."
# Restart SHM NPS
Enable-AzVM -Name $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg
# Wait 2 minutes for NPS to complete post-restart boot and start NPS services
Add-LogMessage -Level Info "Waiting 2 minutes for NPS services to start..."
Start-Sleep 120

# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;