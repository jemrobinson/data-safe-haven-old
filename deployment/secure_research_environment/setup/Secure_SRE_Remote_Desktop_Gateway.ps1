param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $false, HelpMessage = "Do a 'dry run' against the Let's Encrypt staging server.")]
    [switch]$dryRun,
    [Parameter(Mandatory = $false, HelpMessage = "Force the installation step even for dry runs.")]
    [switch]$forceInstall
)

Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop


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


# Disable legacy TLS on the RDS gateway
# -------------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Disable_Legacy_TLS.ps1')" -shmId $shmId -sreId $sreId }


# Configure CAP and RAP settings on the RDS gateway
# -------------------------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Configure_SRE_RDS_CAP_And_RAP.ps1')" -shmId $shmId -sreId $sreId }


# Update the SSL certificates on the RDS gateway
# ----------------------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Update_SRE_SSL_Certificate.ps1')" -shmId $shmId -sreId $sreId -dryRun:$dryRun -forceInstall:$forceInstall }


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
