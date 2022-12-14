param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.OperationalInsights -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureAutomation -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureMonitor -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureOperationalInsights -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzurePrivateDns -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Create resource group if it does not exist
# ------------------------------------------
$null = Deploy-ResourceGroup -Name $config.monitoring.rg -Location $config.location


# Deploy log analytics workspace
# ------------------------------
$workspace = Deploy-LogAnalyticsWorkspace -Name $config.monitoring.loggingWorkspace.name -ResourceGroupName $config.monitoring.rg -Location $config.location


# Deploy automation account and connect to log analytics
# ------------------------------------------------------
$account = Deploy-AutomationAccount -Name $config.monitoring.automationAccount.name -ResourceGroupName $config.monitoring.rg -Location $config.location
$null = Connect-AutomationAccountLogAnalytics -AutomationAccountName $account.AutomationAccountName -LogAnalyticsWorkspace $workspace


# Connect log analytics workspace to private link scope
# Note that we cannot connect a private endpoint directly to a log analytics workspace
# ------------------------------------------------------------------------------------
$logAnalyticsLink = Deploy-MonitorPrivateLinkScope -Name $config.monitoring.privatelink.name -ResourceGroupName $config.monitoring.rg
$null = Connect-PrivateLinkToLogWorkspace -LogAnalyticsWorkspace $workspace -PrivateLinkScope $logAnalyticsLink


# Create private endpoints for the automation account and log analytics link
# --------------------------------------------------------------------------
$monitoringSubnet = Get-Subnet -Name $config.network.vnet.subnets.monitoring.name -VirtualNetworkName $config.network.vnet.name -ResourceGroupName $config.network.vnet.rg
$accountEndpoint = Deploy-AutomationAccountEndpoint -Account $account -Subnet $monitoringSubnet
$logAnalyticsEndpoint = Deploy-MonitorPrivateLinkScopeEndpoint -PrivateLinkScope $logAnalyticsLink -Subnet $monitoringSubnet -Location $config.location


# Create private DNS records for each endpoint DNS entry
# ------------------------------------------------------
$DnsConfigs = $accountEndpoint.CustomDnsConfigs + $logAnalyticsEndpoint.CustomDnsConfigs
# Only these exact domains are available as privatelink.{domain} through Azure Private DNS
# See https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-dns
$PrivateLinkDomains = @(
    "agentsvc.azure-automation.net",
    "azure-automation.net", # note this must come after 'agentsvc.azure-automation.net'
    "blob.core.windows.net",
    "monitor.azure.com",
    "ods.opinsights.azure.com",
    "oms.opinsights.azure.com"
)
foreach ($DnsConfig in $DnsConfigs) {
    $BaseDomain = $PrivateLinkDomains | Where-Object { $DnsConfig.Fqdn.Endswith($_) } | Select-Object -First 1 # we want the first (most specific) match
    if ($BaseDomain) {
        $privateZone = Deploy-PrivateDnsZone -Name "privatelink.${BaseDomain}" -ResourceGroup $config.network.vnet.rg
        $recordName = $DnsConfig.Fqdn.Substring(0, $DnsConfig.Fqdn.IndexOf($BaseDomain) - 1)
        $null = Deploy-PrivateDnsRecordSet -Name $recordName -ZoneName $privateZone.Name -ResourceGroupName $privateZone.ResourceGroupName -PrivateIpAddresses $DnsConfig.IpAddresses -Ttl 10
        # Connect the private DNS zones to all virtual networks in the SHM
        # Note that this must be done before connecting the VMs to log analytics to ensure that they use the private link
        foreach ($virtualNetwork in Get-VirtualNetwork -ResourceGroupName $config.network.vnet.rg) {
            $null = Connect-PrivateDnsToVirtualNetwork -DnsZone $privateZone -VirtualNetwork $virtualNetwork
        }
    } else {
        Add-LogMessage -Level Fatal "No zone created for '$($DnsConfig.Fqdn)'!"
    }
}


# Schedule updates for all connected VMs
# --------------------------------------
$null = Deploy-LogAnalyticsSolution -Workspace $workspace -SolutionType "Updates"
$shmQuery = Deploy-AutomationAzureQuery -Account $account -ResourceGroups (Get-ShmResourceGroups -shmConfig $config)
$localTimeZone = Get-TimeZone -Id $config.time.timezone.linux
# Create Windows VM virus definitions update schedule
$windowsDailySchedule = Deploy-AutomationScheduleInDays -Account $account `
                                                        -Name "shm-$($config.id)-windows-definitions".ToLower() `
                                                        -Time "$($config.monitoring.updateServers.schedule.daily_definition_updates.hour):$($config.monitoring.updateServers.schedule.daily_definition_updates.minute)" `
                                                        -TimeZone $localTimeZone
$null = Register-VmsWithAutomationSchedule -Account $account `
                                           -DurationHours 1 `
                                           -IncludedUpdateCategories @("Definition") `
                                           -Query $shmQuery `
                                           -Schedule $windowsDailySchedule `
                                           -VmType "Windows"
# Create Windows VM other updates schedule
$windowsWeeklySchedule = Deploy-AutomationScheduleInDays -Account $account `
                                                         -DayInterval 7 `
                                                         -Name "shm-$($config.id)-windows-updates".ToLower() `
                                                         -StartDayOfWeek $config.monitoring.updateServers.schedule.weekly_system_updates.day `
                                                         -Time "$($config.monitoring.updateServers.schedule.weekly_system_updates.hour):$($config.monitoring.updateServers.schedule.weekly_system_updates.minute)" `
                                                         -TimeZone $localTimeZone
$null = Register-VmsWithAutomationSchedule -Account $account `
                                           -DurationHours 3 `
                                           -IncludedUpdateCategories @("Critical", "FeaturePack", "Security", "ServicePack", "Tools", "Unclassified", "UpdateRollup", "Updates") `
                                           -Query $shmQuery `
                                           -Schedule $windowsWeeklySchedule `
                                           -VmType "Windows"
# Create Linux VM update schedule
$linuxWeeklySchedule = Deploy-AutomationScheduleInDays -Account $account `
                                                       -DayInterval 7 `
                                                       -Name "shm-$($config.id)-linux-updates".ToLower() `
                                                       -StartDayOfWeek $config.monitoring.updateServers.schedule.weekly_system_updates.day `
                                                       -Time "$($config.monitoring.updateServers.schedule.weekly_system_updates.hour):$($config.monitoring.updateServers.schedule.weekly_system_updates.minute)" `
                                                       -TimeZone $localTimeZone
$null = Register-VmsWithAutomationSchedule -Account $account `
                                           -DurationHours 3 `
                                           -IncludedUpdateCategories @("Critical", "Other", "Security", "Unclassified") `
                                           -Query $shmQuery `
                                           -Schedule $linuxWeeklySchedule `
                                           -VmType "Linux"


# Enable the collection of syslog logs from Linux hosts
# -----------------------------------------------------
$null = Enable-AzOperationalInsightsLinuxSyslogCollection -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name
# Delete all existing syslog sources
$sources = Get-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Kind 'LinuxSysLog'
foreach ($source in $sources) {
    $null = Remove-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Name $source.Name -Force
}
# Syslog facilities:
#   See
#     - https://wiki.gentoo.org/wiki/Rsyslog#Facility
#     - https://tools.ietf.org/html/rfc5424 (page 10)
#     - https://rsyslog.readthedocs.io/en/latest/configuration/filters.html
$facilities = @{
    "auth"     = "security/authorization messages";
    "authpriv" = "non-system authorization messages";
    "cron"     = "clock daemon";
    "daemon"   = "system daemons";
    "ftp"      = "FTP daemon";
    "kern"     = "kernel messages";
    "lpr"      = "line printer subsystem";
    "mail"     = "mail system";
    "news"     = "network news subsystem";
    "syslog"   = "messages generated internally by syslogd";
    "user"     = "user-level messages";
    "uucp"     = "UUCP subsystem";
}
# Syslog severities:
#   See
#     - https://wiki.gentoo.org/wiki/Rsyslog#Severity
#     - https://tools.ietf.org/html/rfc5424 (page 11)
#
#   Emergency:     system is unusable
#   Alert:         action must be taken immediately
#   Critical:      critical conditions
#   Error:         error conditions
#   Warning:       warning conditions
#   Notice:        normal but significant condition
#   Informational: informational messages
#   Debug:         debug-level messages
foreach ($facility in $facilities.GetEnumerator()) {
    $null = New-AzOperationalInsightsLinuxSyslogDataSource -CollectAlert `
                                                           -CollectCritical `
                                                           -CollectDebug `
                                                           -CollectEmergency `
                                                           -CollectError `
                                                           -CollectInformational `
                                                           -CollectNotice `
                                                           -CollectWarning `
                                                           -Facility $facility.Key `
                                                           -Force `
                                                           -Name "Linux-syslog-$($facility.Key)" `
                                                           -ResourceGroupName $workspace.ResourceGroupName `
                                                           -WorkspaceName $workspace.Name
    if ($?) {
        Add-LogMessage -Level Success "Logging activated for '$($facility.Key)' syslog facility [$($facility.Value)]."
    } else {
        Add-LogMessage -Level Fatal "Failed to activate logging for '$($facility.Key)' syslog facility [$($facility.Value)]!"
    }
}


# Ensure required Windows event logs are collected
# ------------------------------------------------
Add-LogMessage -Level Info "Ensuring required Windows event logs are being collected...'"
# Delete all existing event log sources
$sources = Get-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Kind 'WindowsEvent'
foreach ($source in $sources) {
    $null = Remove-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Name $source.Name -Force
}
$eventLogNames = @(
    "Active Directory Web Services"
    "Directory Service",
    "DFS Replication",
    "DNS Server",
    "Microsoft-Windows-Security-Netlogon/Operational",
    "Microsoft-Windows-Winlogon/Operational",
    "System"
)
foreach ($eventLogName in $eventLogNames) {
    $sourceName = "windows-event-$eventLogName".Replace("%", "percent").Replace("/", "-per-").Replace(" ", "-").ToLower()
    $null = New-AzOperationalInsightsWindowsEventDataSource -CollectErrors `
                                                            -CollectInformation `
                                                            -CollectWarnings `
                                                            -EventLogName $eventLogName `
                                                            -Name $sourceName `
                                                            -ResourceGroupName $workspace.ResourceGroupName `
                                                            -WorkspaceName $workspace.Name
    if ($?) {
        Add-LogMessage -Level Success "Logging activated for '$eventLogName'."
    } else {
        Add-LogMessage -Level Fatal "Failed to activate logging for '$eventLogName'!"
    }
}


# Ensure require Windows performance counters are collected
# ---------------------------------------------------------
Add-LogMessage -Level Info "Ensuring required Windows performance counters are being collected...'"
# Delete all existing performance counter log sources
$sources = Get-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Kind 'WindowsPerformanceCounter'
foreach ($source in $sources) {
    $null = Remove-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Name $source.Name -Force
}
$counters = @(
    @{setName = "LogicalDisk"; counterName = "Avg. Disk sec/Read" },
    @{setName = "LogicalDisk"; counterName = "Avg. Disk sec/Write" },
    @{setName = "LogicalDisk"; counterName = "Current Disk Queue Length" },
    @{setName = "LogicalDisk"; counterName = "Disk Reads/sec" },
    @{setName = "LogicalDisk"; counterName = "Disk Transfers/sec" },
    @{setName = "LogicalDisk"; counterName = "Disk Writes/sec" },
    @{setName = "LogicalDisk"; counterName = "Free Megabytes" },
    @{setName = "Memory"; counterName = "Available MBytes" },
    @{setName = "Memory"; counterName = "% Committed Bytes In Use" },
    @{setName = "LogicalDisk"; counterName = "% Free Space" },
    @{setName = "Processor"; counterName = "% Processor Time" },
    @{setName = "System"; counterName = "Processor Queue Length" }
)
foreach ($counter in $counters) {
    $sourceName = "windows-counter-$($counter.setName)-$($counter.counterName)".Replace("%", "percent").Replace("/", "-per-").Replace(" ", "-").ToLower()
    $null = New-AzOperationalInsightsWindowsPerformanceCounterDataSource -CounterName $counter.counterName `
                                                                         -InstanceName "*" `
                                                                         -IntervalSeconds 60 `
                                                                         -Name $sourceName `
                                                                         -ObjectName $counter.setName `
                                                                         -ResourceGroupName $workspace.ResourceGroupName `
                                                                         -WorkspaceName $workspace.Name
    if ($?) {
        Add-LogMessage -Level Success "Logging activated for '$($counter.setName)/$($counter.counterName)'."
    } else {
        Add-LogMessage -Level Fatal "Failed to activate logging for '$($counter.setName)/$($counter.counterName)'!"
    }
}


# Activate required Intelligence Packs
# ------------------------------------
Add-LogMessage -Level Info "Ensuring required Log Analytics Intelligence Packs are enabled...'"
$packNames = @(
    "AgentHealthAssessment",
    "AzureActivity",
    "AzureNetworking",
    "AzureResources",
    "AntiMalware",
    "AzureAutomation",
    "CapacityPerformance",
    "ChangeTracking",
    "DnsAnalytics",
    "InternalWindowsEvent",
    "LogManagement",
    "NetFlow",
    "NetworkMonitoring",
    "ServiceMap",
    "Updates",
    "VMInsights",
    "WindowsDefenderATP",
    "WindowsFirewall",
    "WinLog"
)
# Ensure only the selected intelligence packs are enabled
$packsAvailable = Get-AzOperationalInsightsIntelligencePack -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name
foreach ($pack in $packsAvailable) {
    if ($pack.Name -in $packNames) {
        if ($pack.Enabled) {
            Add-LogMessage -Level InfoSuccess "'$($pack.Name)' Intelligence Pack already enabled."
        } else {
            $null = Set-AzOperationalInsightsIntelligencePack -IntelligencePackName $pack.Name -WorkspaceName $workspace.Name -ResourceGroupName $workspace.ResourceGroupName -Enabled $true
            if ($?) {
                Add-LogMessage -Level Success "'$($pack.Name)' Intelligence Pack enabled."
            } else {
                Add-LogMessage -Level Fatal "Failed to enable '$($pack.Name)' Intelligence Pack!"
            }
        }
    } else {
        if ($pack.Enabled) {
            $null = Set-AzOperationalInsightsIntelligencePack -IntelligencePackName $pack.Name -WorkspaceName $workspace.Name -ResourceGroupName $workspace.ResourceGroupName -Enabled $false
            if ($?) {
                Add-LogMessage -Level Success "'$($pack.Name)' Intelligence Pack disabled."
            } else {
                Add-LogMessage -Level Fatal "Failed to disable '$($pack.Name)' Intelligence Pack!"
            }
        } else {
            Add-LogMessage -Level InfoSuccess "'$($pack.Name)' Intelligence Pack already disabled."
        }
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
