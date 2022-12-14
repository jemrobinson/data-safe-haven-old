# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Base-64 encoded NPS secret")]
    [ValidateNotNullOrEmpty()]
    [string]$npsSecretB64,
    [Parameter(HelpMessage = "IP address of RDS gateway")]
    [ValidateNotNullOrEmpty()]
    [string]$rdsGatewayIp,
    [Parameter(HelpMessage = "FQDN of RDS gateway")]
    [ValidateNotNullOrEmpty()]
    [string]$rdsGatewayFqdn,
    [Parameter(HelpMessage = "SRE ID")]
    [ValidateNotNullOrEmpty()]
    [string]$sreId
)


# Deserialise Base-64 encoded variables
# -------------------------------------
$npsSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($npsSecretB64))


# Ensure that RADIUS client is registered
# ---------------------------------------
Write-Output "Ensuring that RADIUS client '$rdsGatewayFqdn' is registered..."
if (Get-NpsRadiusClient | Where-Object { $_.Name -eq "$rdsGatewayFqdn" }) {
    Write-Output " [o] RADIUS client '$rdsGatewayFqdn' already exists"
    Write-Output "Updating RADIUS client '$rdsGatewayFqdn' at '$rdsGatewayIp'..."
    $null = Set-NpsRadiusClient -Address $rdsGatewayIp -Name "$rdsGatewayFqdn" -SharedSecret "$npsSecret"
    if ($?) {
        Write-Output " [o] Successfully updated RADIUS client"
    } else {
        Write-Output " [x] Failed to update RADIUS client!"
    }
} else {
    Write-Output "Creating RADIUS client '$rdsGatewayFqdn' at '$rdsGatewayIp'..."
    $null = New-NpsRadiusClient -Address $rdsGatewayIp -Name "$rdsGatewayFqdn" -SharedSecret "$npsSecret"
    if ($?) {
        Write-Output " [o] Successfully created RADIUS client"
    } else {
        Write-Output " [x] Failed to create RADIUS client!"
    }
}


# Add RDS gateway inbound rule
# ----------------------------
Write-Output "Adding RDS gateway inbound rule..."
$ruleName = "SRE $($sreId.ToUpper()) RDS Gateway RADIUS inbound ($rdsGatewayIp)"
if (Get-NetFirewallRule | Where-Object { $_.DisplayName -eq "$ruleName" }) {
    Write-Output " [o] Inbound RADIUS firewall rule '$ruleName' already exists"
    Write-Output "Updating '$ruleName' inbound RADIUS firewall rule for $rdsGatewayFqdn ($rdsGatewayIp)..."
    $null = Set-NetFirewallRule -DisplayName $ruleName -Direction Inbound -RemoteAddress $rdsGatewayIp -Action Allow -Protocol UDP -LocalPort "1645", "1646", "1812", "1813" -Profile Domain -Enabled True
    if ($?) {
        Write-Output " [o] Successfully updated RDS gateway inbound rule"
    } else {
        Write-Output " [x] Failed to update RDS gateway inbound rule!"
    }
} else {
    Write-Output "Adding '$ruleName' inbound RADIUS firewall rule for $rdsGatewayFqdn ($rdsGatewayIp)..."
    $null = New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -RemoteAddress $rdsGatewayIp -Action Allow -Protocol UDP -LocalPort "1645", "1646", "1812", "1813" -Profile Domain -Enabled True
    if ($?) {
        Write-Output " [o] Successfully added RDS gateway inbound rule"
    } else {
        Write-Output " [x] Failed to add RDS gateway inbound rule!"
    }
}
