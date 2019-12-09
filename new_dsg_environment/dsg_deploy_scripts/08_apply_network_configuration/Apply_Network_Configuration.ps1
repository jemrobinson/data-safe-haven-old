param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext;
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

Write-Host ("Applying network configuration for DSG" + $config.dsg.id `
           + " (Tier " + $config.dsg.tier + "), hosted on subscription '" + `
           $config.dsg.subscriptionName + "'.")

# =======================================================================
# === Ensure RDS session hosts are bound to most restricted Linux NSG ===
# =======================================================================

# Set names of Network Security Group (NSG) and Network Interface Cards (NICs)
$sh1NicName = $config.dsg.rds.sessionHost1.vmName + "_NIC1";
$sh2NicName = $config.dsg.rds.sessionHost2.vmName + "_NIC1";
$dataServerNicName = $config.dsg.dataserver.vmName + "_NIC1";

# Set Azure Network Security Group (NSG) and Network Interface Cards (NICs) objects
# $nsgSessionHosts = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.nsg.sessionHosts.name;
$nsgSessionHosts = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg | Where-Object { $_.Name -Like "NSG*SESSION*" }
$sh1Nic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.rds.rg -Name $sh1NicName;
$sh2Nic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.rds.rg -Name $sh2NicName;
$dataServerNic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.dataserver.rg -Name $dataServerNicName;

# Assign RDS Session Host NICs to Session Hosts NSG
Write-Host (" - Associating RDS Session Hosts with '" + $nsgSessionHosts.Name + "' NSG")
$sh1Nic.NetworkSecurityGroup = $nsgSessionHosts;
$_ = ($sh1Nic | Set-AzNetworkInterface);
$sh2Nic.NetworkSecurityGroup = $nsgSessionHosts;
$_ = ($sh2Nic | Set-AzNetworkInterface);
$dataServerNic.NetworkSecurityGroup = $nsgSessionHosts;
$_ = ($dataServerNic | Set-AzNetworkInterface);

# Wait a short while for NIC association to complete
Start-Sleep -Seconds 5
Write-Host ("   - Done: NICs associated with '" + $nsgSessionHosts.Name + "' NSG")
 @($nsgSessionHosts.NetworkInterfaces) | ForEach-Object{Write-Host ("     - " + $_.Id.Split("/")[-1])}

# ====================================================================
# === Ensure Webapp servers are bound to most restricted Linux NSG ===
# ====================================================================

# Set names of Network Security Group (NSG) and Network Interface Cards (NICs)
$gitlabNicName = $config.dsg.linux.gitlab.vmName + "_NIC1";
$hackMdNicName = $config.dsg.linux.hackmd.vmName + "_NIC1";

# Set Azure Network Security Group (NSG) and Network Interface Cards (NICs) objects
$nsgLinux = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.nsg;
$gitlabNic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.linux.rg -Name $gitlabNicName;
$hackMdNic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.linux.rg -Name $hackMdNicName;
Write-Host (" - Associating Web App Servers with '" + $nsgLinux.Name + "' NSG")

# Assign Webapp server NICs to Linux VM NSG
$gitlabNic.NetworkSecurityGroup = $nsgLinux;
$_ = ($gitlabNic | Set-AzNetworkInterface);
$hackMdNic.NetworkSecurityGroup = $nsgLinux;
$_ = ($hackMdNic | Set-AzNetworkInterface);

# Wait a short while for NIC association to complete
Start-Sleep -Seconds 5
Write-Host ("   - Done: NICs associated with '" + $nsgLinux.Name + "' NSG")
@($nsgLinux.NetworkInterfaces) | ForEach-Object{Write-Host ("   -   " + $_.Id.Split("/")[-1])}

# ==================================================
# === Update RDS Gateway NSG to match DSG config ===
# ==================================================

# Update RDS Gateway NSG inbound access rule
# $nsgGateway = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.nsg.gateway.name;
$nsgGateway = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg | Where-Object { $_.Name -Like "NSG*SERVER*" }
$httpsInRuleName = "HTTPS_In"
$httpsInRuleBefore = Get-AzNetworkSecurityRuleConfig -Name $httpsInRuleName -NetworkSecurityGroup $nsgGateway;

# Load allowed sources into an array, splitting on commas and trimming any whitespace from
# each item to avoid "invalid Address prefix" errors caused by extraneous whitespace
$allowedSources = ($config.dsg.rds.nsg.gateway.allowedSources.Split(',') | ForEach-Object{$_.Trim()})

Write-Host (" - Updating '" + $httpsInRuleName + "' rule on '" + $nsgGateway.name + "' NSG to '" `
            + $httpsInRuleBefore.Access  + "' access from '" + $allowedSources `
            + "' (was previously '" + $httpsInRuleBefore.SourceAddressPrefix + "')")

$nsgGatewayHttpsInRuleParams = @{
  Name = $httpsInRuleName
  NetworkSecurityGroup = $nsgGateway
  Description = "Allow HTTPS inbound to RDS server"
  Access = "Allow"
  Direction = "Inbound"
  SourceAddressPrefix = $allowedSources
  Protocol = "TCP"
  SourcePortRange = "*"
  DestinationPortRange = "443"
  DestinationAddressPrefix = "*"
  Priority = "101"
}

# Update rule and NSG (both are required)
$_ = Set-AzNetworkSecurityRuleConfig @nsgGatewayHttpsInRuleParams;
$_ = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgGateway;

# Confirm update has being successfully applied
$httpsInRuleAfter = Get-AzNetworkSecurityRuleConfig -Name $httpsInRuleName -NetworkSecurityGroup $nsgGateway;

Write-Host ("   - Done: '" + $httpsInRuleName + "' on '" + $nsgGateway.name + "' NSG will now '" + $httpsInRuleAfter.Access `
            + "' access from '" + $httpsInRuleAfter.SourceAddressPrefix + "'")

# =======================================================
# === Update restricted Linux NSG to match DSG config ===
# =======================================================

# Update RDS Gateway NSG inbound access rule
# $nsgLinux = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.nsg;
$nsgLinux = Get-AzNetworkSecurityGroup -Name $config.dsg.linux.nsg
$internetOutRuleName = "Internet_Out"
$internetOutRuleBefore = Get-AzNetworkSecurityRuleConfig -Name $internetOutRuleName -NetworkSecurityGroup $nsgLinux;

# Outbound access to Internet is Allowed for Tier 0 and 1 but Denied for Tier 2 and above
$access = $config.dsg.rds.nsg.gateway.outboundInternet
$allowedSources = ($config.dsg.rds.nsg.gateway.allowedSources.Split(',') | ForEach-Object{$_.Trim()})

Write-Host (" - Updating '" + $internetOutRuleName + "' rule on '" + $nsgLinux.name + "' NSG to '" `
            + $access  + "' access to '" + $internetOutRuleBefore.DestinationAddressPrefix `
            + "' (was previously '" + $internetOutRuleBefore.Access + "')")

$nsgLinuxInternetOutRuleParams = @{
  Name = $internetOutRuleName
  NetworkSecurityGroup = $nsgLinux
  Description = "Control outbound internet access from user accessible VMs"
  Access = $access
  Direction = "Outbound"
  SourceAddressPrefix = "VirtualNetwork"
  Protocol = "*"
  SourcePortRange = "*"
  DestinationPortRange = "*"
  DestinationAddressPrefix = "Internet"
  Priority = "4000"
}

# Update rule and NSG (both are required)
$_ = Set-AzNetworkSecurityRuleConfig @nsgLinuxInternetOutRuleParams;
$_ = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgLinux;

# Confirm update has being successfully applied
$internetOutRuleAfter = Get-AzNetworkSecurityRuleConfig -Name $internetOutRuleName -NetworkSecurityGroup $nsgLinux;

Write-Host ("   - Done: '" + $internetOutRuleName + "' on '" + $nsgLinux.name + "' NSG will now '" + $internetOutRuleAfter.Access `
            + "' access to '" + $internetOutRuleAfter.DestinationAddressPrefix + "'")

# ==================================================
# === Ensure DSG is peered to correct mirror set ===
# ==================================================
# We do this as the Tier of the DSG may have changed and we want to ensure we are peered
# to the correct mirror set fo its current Tier and not peered to the mirror set for
# any other Tier
$peeringDir = (Join-Path $PSScriptRoot ".." "09_mirror_peerings" -Resolve)
$peeringScriptPath = (Join-Path $peeringDir "Configure_Mirror_Peering.ps1"  -Resolve)

# (Re-)configure Mirror peering for the DSG
Write-Host ("Configuring mirror peering")
Invoke-Expression -Command "$peeringScriptPath -dsgId $dsgId";


# Update DSG mirror lookup
# ------------------------
Write-Host -ForegroundColor DarkCyan "Determining correct URLs for package mirrors..."
if($config.dsg.mirrors.cran.ip) {
    $CRAN_MIRROR_URL = "http://$($config.dsg.mirrors.cran.ip)"
} else {
    $CRAN_MIRROR_URL = "https://cran.r-project.org"
}
if($config.dsg.mirrors.pypi.ip) {
    $PYPI_MIRROR_URL = "http://$($config.dsg.mirrors.pypi.ip):3128"
} else {
    $PYPI_MIRROR_URL = "https://pypi.org"
}
# We want to extract the hostname from PyPI URLs in either of the following forms
# 1. http://10.20.2.20:3128 => 10.20.2.20
# 2. https://pypi.org       => pypi.org
$PYPI_MIRROR_HOST = ""
if ($PYPI_MIRROR_URL -match "https*:\/\/([^:]*)[:0-9]*") { $PYPI_MIRROR_HOST = $Matches[1] }
Write-Host -ForegroundColor DarkGreen " [o] CRAN: '$CRAN_MIRROR_URL'"
Write-Host -ForegroundColor DarkGreen " [o] PyPI server: '$PYPI_MIRROR_URL'"
Write-Host -ForegroundColor DarkGreen " [o] PyPI host: '$PYPI_MIRROR_HOST'"

# Set PyPI and CRAN locations on the compute VM
# ---------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
$computeVMs = Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg | % {$_.Name }
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "update_mirror_settings.sh"
foreach ($vmName in $computeVMs) {
    Write-Host "Setting PyPI and CRAN locations on compute VM: $($vmName)"
    $params = @{
      CRAN_MIRROR_URL = "`"$CRAN_MIRROR_URL`""
      PYPI_MIRROR_URL = "`"$PYPI_MIRROR_URL`""
      PYPI_MIRROR_HOST = "`"$PYPI_MIRROR_HOST`""
    }
    $result = Invoke-AzVMRunCommand -ResourceGroupName $config.dsg.dsvm.rg -Name $vmName `
                                    -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
    $success = $?
    Write-Output $result.Value
    if ($success) {
        Write-Host "Setting PyPI and CRAN locations on compute VM was successful"
    }
}


# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;