param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../../DsgConfig.psm1 -Force

# Get DSG config and store original subscription
$config = Get-DsgConfig($dsgId);
$originalSubscription = Get-AzContext;

# Unpeer any existing networks before (re-)establishing correct peering for DSG
# -----------------------------------------------------------------------------
Write-Host "Removing all existing mirror peerings..."
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
$dsgVnet = Get-AzVirtualNetwork -Name $config.dsg.network.vnet.name -ResourceGroupName $config.dsg.network.vnet.rg

# Get all mirror VNets from management subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
$mirrorVnets = Get-AzVirtualNetwork | Where-Object { $_.Name -Like "*PKG_MIRRORS*" }

# Remove SHM side of mirror peerings involving this SRE
ForEach($mirrorVnet in $mirrorVnets) {
    $mirrorPeerings = Get-AzVirtualNetworkPeering -Name "*" -VirtualNetwork $mirrorVnet.Name -ResourceGroupName $mirrorVnet.ResourceGroupName
    ForEach($mirrorPeering in $mirrorPeerings) {
        # Remove peerings that involve this SRE
        If($mirrorPeering.RemoteVirtualNetwork.Id -eq $dsgVnet.Id) {
            Write-Host " [ ] Removing peering $($mirrorPeering.Name): $($mirrorPeering.VirtualNetworkName) <-> $($dsgVnet.Name)"
            $_ = Remove-AzVirtualNetworkPeering -Name $mirrorPeering.Name -VirtualNetworkName $mirrorVnet.Name -ResourceGroupName $mirrorVnet.ResourceGroupName -Force;
            if ($?) {
                Write-Host " [o] Peering removal succeeded"
            } else {
                Write-Host " [x] Peering removal failed!"
            }
        }
    }
}

# Remove peering to this SRE from each SHM mirror network
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
$dsgPeerings = Get-AzVirtualNetworkPeering -Name "*" -VirtualNetwork $dsgVnet.Name -ResourceGroupName $dsgVnet.ResourceGroupName
Write-Host "dsgPeerings: $dsgPeerings"
ForEach($dsgPeering in $dsgPeerings) {
    # Remove peerings that involve any of the mirror VNets
    $peeredVnets = $mirrorVnets | Where-Object { $_.Id -eq $dsgPeering.RemoteVirtualNetwork.Id }
    ForEach($mirrorVnet in $peeredVnets) {
        Write-Host " [ ] Removing peering $($dsgPeering.Name): $($dsgPeering.VirtualNetworkName) <-> $($mirrorVnet.Name)"
        $_ = Remove-AzVirtualNetworkPeering -Name $dsgPeering.Name -VirtualNetworkName $dsgVnet.Name -ResourceGroupName $dsgVnet.ResourceGroupName -Force;
        if ($?) {
            Write-Host " [o] Peering removal succeeded"
        } else {
            Write-Host " [x] Peering removal failed!"
        }
    }
}


# Switch back to original subscription
$_ = Set-AzContext -Context $originalSubscription;
