Import-Module Az
Import-Module $PSScriptRoot/../../../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../../common/Security.psm1 -Force

Function Add-DevSqlServer {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
        [string]$SreId,       
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter a name for the SQL Server VM")]
        [string]$SqlServerName,       
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter the IP address for the VM")]
        [string]$SqlServerIpAddress       
    )

    $config = Get-SreConfig $sreId

    $params = @{
        sreId = $SreId
        subnetName = $config.sre.network.subnets.mssqldev.name
        subnetAddressPrefix = $config.sre.network.subnets.mssqldev.cidr
        resourceGroupName = $config.sre.mssqldev.rg
        sqlServerName = $SqlServerName
        sqlServerEdition = "sqldev"
        sqlServerVmSize = "Standard_GS1"
        sqlServerIpAddress = $SqlServerIpAddress
        sqlServerSsisDisabled = 0
    }

    $_ = Add-SqlServer @params
}

Export-ModuleMember -Function Add-DevSqlServer

Function Add-EtlSqlServer {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
        [string]$SreId,       
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter a name for the SQL Server VM")]
        [string]$SqlServerName,       
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter the IP address for the VM")]
        [string]$SqlServerIpAddress       
    )

    $config = Get-SreConfig $sreId

    $params = @{
        sreId = $SreId
        subnetName = $config.sre.network.subnets.mssqletl.name
        subnetAddressPrefix = $config.sre.network.subnets.mssqletl.cidr
        resourceGroupName = $config.sre.mssqletl.rg
        sqlServerName = $SqlServerName
        sqlServerEdition = "enterprise"
        sqlServerVmSize = "Standard_GS1"
        sqlServerIpAddress = $SqlServerIpAddress
        sqlServerSsisDisabled = 0
    }

    $_ = Add-SqlServer @params
}

Export-ModuleMember -Function Add-EtlSqlServer

Function Add-DataSqlServer {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
        [string]$SreId,       
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter a name for the SQL Server VM")]
        [string]$SqlServerName,       
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter the IP address for the VM")]
        [string]$SqlServerIpAddress       
    )

    $config = Get-SreConfig $sreId

    $params = @{
        sreId = $SreId
        subnetName = $config.sre.network.subnets.mssqldata.name
        subnetAddressPrefix = $config.sre.network.subnets.mssqldata.cidr
        resourceGroupName = $config.sre.mssqldata.rg
        sqlServerName = $SqlServerName
        sqlServerEdition = "enterprise"
        sqlServerVmSize = "Standard_GS2"
        sqlServerIpAddress = $SqlServerIpAddress
        sqlServerSsisDisabled = 1
    }

    $_ = Add-SqlServer @params
}

Export-ModuleMember -Function Add-DataSqlServer

Function Add-SqlServer {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
        [string]$sreId,
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter name of the SRE subnet that will contain the SQL Server")]
        [string]$subnetName,
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter name of the SRE subnet that will contain the SQL Server")]
        [string]$subnetAddressPrefix,
        [Parameter(Position=3, Mandatory = $true, HelpMessage = "Enter name of the resource group that will contain the SQL Server")]
        [string]$resourceGroupName,
        [Parameter(Position=4, Mandatory = $true, HelpMessage = "Enter a name for the SQL Server VM")]
        [string]$sqlServerName,
        [Parameter(Position=5, Mandatory = $true, HelpMessage = "Enter the SQL Server Edition e.g. sqldev or enterprise")]
        [string]$sqlServerEdition,
        [Parameter(Position=6, Mandatory = $true, HelpMessage = "Enter the size of the VM e.g. Standard_GS1 or Standard_GS2")]
        [string]$sqlServerVmSize,
        [Parameter(Position=7, Mandatory = $true, HelpMessage = "Enter the IP address for the VM")]
        [string]$sqlServerIpAddress,
        [Parameter(Position=8, Mandatory = $true, HelpMessage = "Enter whether SSIS should be disabled")]
        [bool]$sqlServerSsisDisabled
    )

    $maximumSqlServerNameLength = 15
    If ($sqlServerName.length -gt $maximumSqlServerNameLength) {
        Add-LogMessage -Level Error "Sql Server Name: $($sqlServerName) is too long.  It needs to be $($maximumSqlServerNameLength) characters or less."
        Return        
    }

    # Get config and original context before changing subscription
    # ------------------------------------------------------------
    $config = Get-SreConfig $sreId
    $originalContext = Get-AzContext
    $_ = Set-AzContext -Subscription $config.sre.subscriptionName

    # Retrieve passwords from the keyvault
    # ------------------------------------
    Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
    $shmDcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminPassword
    $shmDcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.shm.id)admin".ToLower()
    $sreAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dataServerAdminPassword
    $sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()

    # Create resource group if it does not exist
    # ------------------------------------------------------
    $_ = Deploy-ResourceGroup -Name $resourceGroupName -Location $config.sre.location

    # Create subnet if it does not exist
    # ------------------------------------------------------
    $virtualNetwork = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
    $subnet = Deploy-Subnet -Name $subnetName -VirtualNetwork $virtualNetwork -AddressPrefix $subnetAddressPrefix

    Add-LogMessage -Level Info "SQL Server: '$($sqlServerName)' will join subnet: '$($subnet.Id)'..."
   
    # Deploy SQL Server from template
    # --------------------------------
    Add-LogMessage -Level Info "Creating SQL Server: '$($sqlServerName)'' from template..."
    $params = @{
        Location = $config.sre.location;
        Administrator_Password = $sreAdminPassword;
        Administrator_User = $sreAdminUsername;
        DC_Join_Password = $shmDcAdminPassword;
        DC_Join_User = $shmDcAdminUsername;
        BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName;
        Sql_Server_Name = $sqlServerName;
        Sql_Server_Edition = $sqlServerEdition;      
        Domain_Name = $config.shm.domain.fqdn;
        IP_Address = $sqlServerIpAddress;
        SubnetResourceId = $subnet.Id;  
        VM_Size = $sqlServerVmSize
    }

    $templateFile = (Join-Path $PSScriptRoot ".." ".." ".." "arm_templates" "customisations" "mssql" "sre-mssql2019-server-template.json")
    New-AzResourceGroupDeployment -TemplateFile $templateFile -TemplateParameterObject $params -ResourceGroupName $resourceGroupName -Verbose -DeploymentDebugLogLevel "All"

    # Switch back to original subscription
    # ------------------------------------
    $_ = Set-AzContext -Context $originalContext;
}

Export-ModuleMember -Function Add-SqlServer