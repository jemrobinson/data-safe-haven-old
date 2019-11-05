# Load configuration module
# -------------------------
module "configuration" {
  source = "../configuration"
}

variable "dsg_keyVault_dcAdminPassword" {}
variable "dsg_network_subnets_identity_id" {}

# # Explicitly take providers as an argument, or they cannot be referenced
# # ----------------------------------------------------------------------
# provider "azurerm" {}
# provider "azurerm" { alias = "shm_management" }

# Create the storage resource group
# ---------------------------------
resource "azurerm_resource_group" "storage" {
  name     = "${module.configuration.dsg_storage_artifacts_rg}"
  location = "${module.configuration.dsg_location}"
}

# Create storage account and container
# ------------------------------------
resource "azurerm_storage_account" "this" {
  name                     = "${module.configuration.dsg_storage_artifacts_accountName}"
  resource_group_name      = "${azurerm_resource_group.storage.name}"
  location                 = "${module.configuration.dsg_location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
resource "azurerm_storage_container" "this" {
  name                  = "dc-create-scripts"
  storage_account_name  = "${azurerm_storage_account.this.name}"
  container_access_type = "private"
}

# Upload ZIP file with artifacts
# ------------------------------
variable "artifacts_zip" {
  default = "dc-create.zip"
}
resource "azurerm_storage_blob" "this" {
  name                   = "${var.artifacts_zip}"
  # resource_group_name    = "${azurerm_resource_group.storage.name}"
  storage_account_name   = "${azurerm_storage_account.this.name}"
  storage_container_name = "${azurerm_storage_container.this.name}"
  type                   = "Block"
  source                 = "${path.module}/../../../new_dsg_environment/dsg_deploy_scripts/03_create_dc/artifacts/dc-create-scripts/${var.artifacts_zip}"
}

# Get SAS token
# -------------
data "azurerm_storage_account_sas" "this" {
  connection_string = "${azurerm_storage_account.this.primary_connection_string}"
  https_only        = true

  resource_types {
    service   = true
    container = true
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = true
  }

  start  = "${timestamp()}"
  expiry = "${timeadd(timestamp(), "1h")}"

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = true
    add     = false
    create  = false
    update  = false
    process = false
  }

  # lifecycle {
  #   ignore_changes = ["start", "expiry"]
  # }
}

# Create the domain controller resource group
# -------------------------------------------
resource "azurerm_resource_group" "dc" {
  name     = "${module.configuration.dsg_dc_rg}"
  location = "${module.configuration.dsg_location}"
}

# Create storage account for boot diagnostics
# -------------------------------------------
resource "azurerm_storage_account" "bootdiagnostics" {
  name                     = "${module.configuration.dsg_shortName}bootdiagnostics"
  resource_group_name      = "${azurerm_resource_group.dc.name}"
  location                 = "${module.configuration.dsg_location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
# Deploy domain controller
# -----------------------
resource "azurerm_network_interface" "this" {
  name                = "${module.configuration.dsg_dc_vmName}_NIC"
  location            = "${module.configuration.dsg_location}"
  resource_group_name = "${azurerm_resource_group.dc.name}"

  ip_configuration {
    name                          = "domainControllerIPConfig"
    private_ip_address            = "${module.configuration.dsg_dc_ip}"
    private_ip_address_allocation = "Static"
    subnet_id                     = "${var.dsg_network_subnets_identity_id}"
  }
}
resource "azurerm_virtual_machine" "this" {
  name                          = "${module.configuration.dsg_dc_vmName}"
  location                      = "${module.configuration.dsg_location}"
  resource_group_name           = "${azurerm_resource_group.dc.name}"
  network_interface_ids         = ["${azurerm_network_interface.this.id}"]
  vm_size                       = "Standard_B2ms"

  boot_diagnostics {
    enabled     = true
    storage_uri = "${azurerm_storage_account.bootdiagnostics.primary_blob_endpoint}"
  }

  identity {
    type = "SystemAssigned"
  }

  os_profile {
    computer_name  = "${module.configuration.dsg_dc_vmName}"
    admin_username = "${module.configuration.dsg_dc_admin_username}"
    admin_password = "${var.dsg_keyVault_dcAdminPassword}"
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true
    timezone                  = "GMT Standard Time"
  }

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${module.configuration.dsg_dc_vmName}_OS_DISK"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
    disk_size_gb      = "128"
  }

  storage_data_disk {
    name              = "${module.configuration.dsg_dc_vmName}_DATA_DISK"
    caching           = "None"
    create_option     = "Empty"
    managed_disk_type = "Standard_LRS"
    disk_size_gb      = "20"
    lun               = "0"
  }
}


# Create domain controller
# ------------------------
resource "null_resource" "Configure_AD_DC" {
  provisioner "local-exec" {
    command = join(" ", [".'${path.module}/local/Configure_AD_DC.ps1'",
                    "-subscriptionName '${module.configuration.dsg_subscriptionName}'",
                    "-dsgNetbiosName '${module.configuration.dsg_domain_netbiosName}'",
                    "-dsgDn '${module.configuration.dsg_domain_dn}'",
                    "-dsgServerAdminSgName '${module.configuration.dsg_domain_securityGroups_serverAdmins_name}'",
                    "-dsgDcAdminUsername '${module.configuration.dsg_dc_admin_username}'",
                    "-subnetIdentityCidr '${module.configuration.dsg_network_subnets_identity_cidr}'",
                    "-subnetRdsCidr '${module.configuration.dsg_network_subnets_rds_cidr}'",
                    "-subnetDataCidr '${module.configuration.dsg_network_subnets_data_cidr}'",
                    "-shmFqdn '${module.configuration.shm_domain_fqdn}'",
                    "-shmDcIp '${module.configuration.shm_dc_ip}'",
                    "-storageAccountName '${azurerm_storage_account.this.name}'",
                    "-storageContainerName '${azurerm_storage_container.this.name}'",
                    "-sasToken '${data.azurerm_storage_account_sas.this.sas}'",
                    "-pipeSeparatedBlobNames '${azurerm_storage_blob.this.name}'"])
    interpreter = ["pwsh", "-Command"]
  }
}

# resource "azurerm_virtual_machine_extension" "CreateADForest" {
#   depends_on           = [azurerm_virtual_machine.this, azurerm_storage_blob.this]
#   name                 = "CreateADForest"
#   location             = "${module.configuration.dsg_location}"
#   resource_group_name  = "${azurerm_resource_group.dc.name}"
#   virtual_machine_name = "${module.configuration.dsg_dc_vmName}"
#   publisher            = "Microsoft.Powershell"
#   type                 = "DSC"
#   type_handler_version = "2.77"

#   settings = <<SETTINGS
#   {
#     "configuration": {
#       "url": "https://${azurerm_storage_account.this.name}.blob.core.windows.net/${azurerm_storage_container.this.name}/${var.artifacts_zip}",
#       "script": "CreateADPDC.ps1",
#       "function": "CreateADPDC"
#     },
#     "configurationArguments": {
#       "DomainName": "${module.configuration.dsg_domain_fqdn}",
#       "DomainNetBIOSName": "${module.configuration.dsg_domain_netbiosName}",
#     }
#   }
#   SETTINGS
#   protected_settings = <<PROTECTED_SETTINGS
#   {
#     "configurationUrlSasToken": ${data.azurerm_storage_account_sas.this.sas},
#     "configurationArguments": {
#       "AdminCreds": {
#         "UserName": "${module.configuration.dsg_dc_admin_username}",
#         "Password": "${var.dsg_keyVault_dcAdminPassword}"
#       }
#     }
#   PROTECTED_SETTINGS
# }