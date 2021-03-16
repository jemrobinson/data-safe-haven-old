param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Azure Active Directory tenant ID")]
    [string]$tenantId
)

# Connect to the Azure AD
# Note that this must be done in a fresh Powershell session with nothing else imported
# ------------------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name AzureAD.Standard.Preview)) {
    Write-Output "Installing Azure AD Powershell module..."
    $null = Register-PackageSource -Trusted -ProviderName "PowerShellGet" -Name "Posh Test Gallery" -Location https://www.poshtestgallery.com/api/v2/ -ErrorAction SilentlyContinue
    $null = Install-Module AzureAD.Standard.Preview -Repository "Posh Test Gallery" -Force
}
Import-Module AzureAD.Standard.Preview -ErrorAction Stop
Write-Output "Connecting to Azure AD '$tenantId'..."
try {
    $null = Connect-AzureAD -TenantId $tenantId
} catch {
    Write-Output "Please run this script in a fresh Powershell session with no other modules imported!"
    throw
}


Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -Subscription $config.dns.subscriptionName -ErrorAction Stop


# Add the SHM domain record to the Azure AD
# -----------------------------------------
Add-LogMessage -Level Info "Adding SHM domain to AAD..."
# Check if domain name has already been added to AAD. Calling Get-AzureADDomain with no
# arguments avoids having to use a try/catch to handle an expected 404 "Not found exception"
# if the domain has not yet been added.
$aadDomain = Get-AzureADDomain | Where-Object { $_.Name -eq $config.domain.fqdn }
if ($aadDomain) {
    Add-LogMessage -Level InfoSuccess "'$($config.domain.fqdn)' already present as custom domain on SHM AAD."
} else {
    $null = New-AzureADDomain -Name $config.domain.fqdn
    Add-LogMessage -Level Success "'$($config.domain.fqdn)' added as custom domain on SHM AAD."
}

# Verify the SHM domain record for the Azure AD
# ---------------------------------------------
Add-LogMessage -Level Info "Verifying domain on SHM AAD..."
if ($aadDomain.IsVerified) {
    Add-LogMessage -Level InfoSuccess "'$($config.domain.fqdn)' already verified on SHM AAD."
} else {
    # Fetch TXT version of AAD domain verification record set
    $validationRecord = Get-AzureADDomainVerificationDnsRecord -Name $config.domain.fqdn `
    | Where-Object { $_.RecordType -eq "Txt" }
    # Make a DNS TXT Record object containing the validation code
    $validationCode = New-AzDnsRecordConfig -Value $validationRecord.Text

    # Check if this validation record already exists for the domain
    $recordSet = Get-AzDnsRecordSet -RecordType TXT -Name "@" `
        -ZoneName $config.domain.fqdn -ResourceGroupName $config.dns.rg `
        -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        # If no TXT record set exists at all, create a new TXT record set with the domain validation code
        $null = New-AzDnsRecordSet -RecordType TXT -Name "@" `
            -Ttl $validationRecord.Ttl -DnsRecords $validationCode `
            -ZoneName $config.domain.fqdn -ResourceGroupName $config.dns.rg
        Add-LogMessage -Level Success "Verification TXT record added to '$($config.domain.fqdn)' DNS zone."
    } else {
        # Check if the verification TXT record already exists in domain DNS zone
        $existingRecord = $recordSet.Records | Where-Object { $_.Value -eq $validationCode }
        if ($existingRecord) {
            Add-LogMessage -Level InfoSuccess "Verification TXT record already exists in '$($config.domain.fqdn)' DNS zone."
        } else {
            # Add the verification TXT record if it did not already exist
            $null = Add-AzDnsRecordConfig -RecordSet $recordSet -Value $validationCode
            $null = Set-AzDnsRecordSet -RecordSet $recordSet
            Add-LogMessage -Level Success "Verification TXT record added to '$($config.domain.fqdn)' DNS zone."
        }
    }
    # Verify domain on AAD
    $maxTries = 10
    $retryDelaySeconds = 60

    for ($tries = 1; $tries -le $maxTries; $tries++) {
        Add-LogMessage -Level Info "Checking domain verification status on SHM AAD (attempt $tries of $maxTries)..."
        try {
            $null = Confirm-AzureADDomain -Name $config.domain.fqdn
        } catch {
            # Confirm-AzureADDomain throws a 400 BadRequest exception if either the verification TXT record is not
            # found or if the domain is already verified. Checking the exception message text to only ignore these
            # conditions feels error prone. Instead print the exception messahe as a warning and continue with the
            # retry loop
            $ex = $_.Exception
            $errorMessage = $ex.ErrorContent.Message.Value
            Add-LogMessage -Level Warning "$errorMessage"
        }
        $aadDomain = Get-AzureADDomain -Name $config.domain.fqdn
        if ($aadDomain.IsVerified) {
            Add-LogMessage -Level Success "Domain '$($config.domain.fqdn)' is verified on SHM AAD."
            break
        } elseif ($tries -eq $maxTries) {
            Add-LogMessage -Level Fatal "Failed to verify domain after $tries attempts. Please try again later."
        } else {
            Add-LogMessage -Level Warning "Verification check failed. Retrying in $retryDelaySeconds seconds..."
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }
}

# Make domain primary on SHM AAD
# ------------------------------
if ($aadDomain.IsVerified) {
    Add-LogMessage -Level Info "Ensuring '$($config.domain.fqdn)' is primary domain on SHM AAD."
    if ($aadDomain.isDefault) {
        Add-LogMessage -Level InfoSuccess "'$($config.domain.fqdn)' is already primary domain on SHM AAD."
    } else {
        $null = Set-AzureADDomain -Name $config.domain.fqdn -IsDefault $TRUE
        Add-LogMessage -Level Success "Set '$($config.domain.fqdn)' as primary domain on SHM AAD."

    }
}

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
