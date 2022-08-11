param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $false, HelpMessage = "Azure Active Directory tenant ID")]
    [string]$tenantId,
    [Parameter(Mandatory = $false, HelpMessage = "No-op mode which will not remove anything")]
    [Switch]$dryRun
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Automation -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureDataProtection -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# If this SRE uses Guacamole then we need the tenant ID for the SHM AAD
# ---------------------------------------------------------------------
if (($config.sre.remoteDesktop.provider -eq "ApacheGuacamole") -and -not $tenantId) {
    Add-LogMessage -Level Fatal "Tearing down SRE '$($config.sre.id)' requires the -tenantId argument! Use the ID for the '$($config.shm.id)' Azure Active Directory."
}


# Make user confirm before beginning deletion
# -------------------------------------------
$sreResourceGroups = Get-SreResourceGroups -sreConfig $config
if ($dryRun.IsPresent) {
    Add-LogMessage -Level Warning "This would remove $($sreResourceGroups.Count) resource group(s) belonging to SRE '$($config.sre.id)' from '$($config.sre.subscriptionName)'!"
} else {
    Add-LogMessage -Level Warning "This will remove $($sreResourceGroups.Count) resource group(s) belonging to SRE '$($config.sre.id)' from '$($config.sre.subscriptionName)'!"
    $sreResourceGroups | ForEach-Object { Add-LogMessage -Level Warning "... $($_.ResourceGroupName)" }
    $confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
    while ($confirmation -ne "y") {
        if ($confirmation -eq "n") { exit 0 }
        $confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
    }
}

# Remove backup instances and policies. Without this the backup vault cannot be deleted
# -------------------------------------------------------------------------------------
Remove-StorageAccountBackupInstances -ResourceGroupName $config.sre.backup.rg -VaultName $config.sre.backup.vault.name


# Remove SRE resource groups and the resources they contain
# ---------------------------------------------------------
$ResourceGroupNames = Get-SreResourceGroups -sreConfig $config | ForEach-Object { $_.ResourceGroupName }
if ($dryRun.IsPresent) {
    $ResourceGroupNames | ForEach-Object { Add-LogMessage -Level Info "Would attempt to remove $_..." }
} else {
    if ($ResourceGroupNames.Count) { Remove-AllResourceGroups -ResourceGroupNames $ResourceGroupNames -MaxAttempts 60 }
}


# Warn if any resources or groups remain
# --------------------------------------
if (-not $dryRun.IsPresent) {
    $sreResourceGroups = Get-SreResourceGroups -sreConfig $config
    if ($sreResourceGroups) {
        Add-LogMessage -Level Error "There are still $($sreResourceGroups.Count) undeleted resource group(s) remaining!"
        foreach ($resourceGroup in $sreResourceGroups) {
            Add-LogMessage -Level Error "$($resourceGroup.ResourceGroupName)"
            Get-ResourcesInGroup -ResourceGroupName $resourceGroup.ResourceGroupName | ForEach-Object {
                Add-LogMessage -Level Error "... $($_.Name) [$($_.ResourceType)]"
            }
        }
        Add-LogMessage -Level Fatal "Failed to teardown SRE '$($config.sre.id)'!"
    }
}


# Remove residual SRE data from the SHM
# -------------------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "secure_research_environment" "setup" "Remove_SRE_Data_From_SHM.ps1"
if ($dryRun.IsPresent) {
    Add-LogMessage -Level Info "SRE data would be removed from the SHM by running: $scriptPath -shmId $shmId -sreId $sreId"
} else {
    Invoke-Expression -Command "$scriptPath -shmId $shmId -sreId $sreId"
}


# Remove update configuration from the SHM automation account
# -----------------------------------------------------------
try {
    Add-LogMessage -Level Info "Removing update automation for SRE $sreId..."
    $null = Remove-AzAutomationSoftwareUpdateConfiguration -Name "sre-$($config.sre.id.ToLower())-windows" -AutomationAccountName $config.shm.monitoring.automationAccount.name -ResourceGroupName $config.shm.monitoring.rg -ErrorAction Stop
    $null = Remove-AzAutomationSoftwareUpdateConfiguration -Name "sre-$($config.sre.id.ToLower())-linux" -AutomationAccountName $config.shm.monitoring.automationAccount.name -ResourceGroupName $config.shm.monitoring.rg -ErrorAction Stop
    Add-LogMessage -Level Success "Removed update automation for SRE $sreId"
} catch {
    Add-LogMessage -Level Fatal "Failed to remove update automation for SRE $sreId!" -Exception $_.Exception
}


# Tear down the AzureAD application
# ---------------------------------
if ($config.sre.remoteDesktop.provider -eq "ApacheGuacamole") {
    $azureAdApplicationName = "Guacamole SRE $($config.sre.id)"
    if ($dryRun.IsPresent) {
        Add-LogMessage -Level Info "'$azureAdApplicationName' would be removed from Azure Active Directory..."
    } else {
        Add-LogMessage -Level Info "Ensuring that '$azureAdApplicationName' is removed from Azure Active Directory..."
        if (Get-MgContext) { Disconnect-MgGraph } # force a refresh of the Microsoft Graph token before starting
        Connect-MgGraph -TenantId $tenantId -Scopes "Application.ReadWrite.All", "Policy.ReadWrite.ApplicationConfiguration" -ErrorAction Stop
        try {
            Get-MgApplication -Filter "DisplayName eq '$azureAdApplicationName'" | ForEach-Object { Remove-MgApplication -ApplicationId $_.Id }
            Add-LogMessage -Level Success "'$azureAdApplicationName' has been removed from Azure Active Directory"
        } catch {
            Add-LogMessage -Level Fatal "Could not remove '$azureAdApplicationName' from Azure Active Directory!" -Exception $_.Exception
        }
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
